import Foundation
import Testing
@testable import Padawan_Adventures

struct PitBridgeMinigameEngineTests {
    private let poolIDs = ["cat", "dog", "sun", "sat", "hat", "bed"]

    private var pool: [GateWord] {
        poolIDs.map { WordCatalog.imagedFallbackEntry(word: $0) }
    }

    private func makeEngine(
        minWords: Int = 2,
        maxWords: Int = 4,
        letterPosition: GateWordPlugLetterPosition = .ending,
        words: [GateWord]? = nil,
        seed: UInt64 = 42
    ) -> PitBridgeMinigameEngine {
        var engine = PitBridgeMinigameEngine(
            config: .init(
                minWords: minWords,
                maxWords: maxWords,
                letterPosition: letterPosition,
                words: words ?? pool
            ),
            rng: PitSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = PitBridgeMinigameEngine(
            config: .init(words: pool)
        )
        #expect(!engine.isActive)
        #expect(engine.words.isEmpty)
        #expect(engine.choices.isEmpty)
        #expect(engine.outcome == nil)
    }

    @Test func beginPicksWordCountWithinRange() {
        for seed in UInt64(1)...UInt64(40) {
            let engine = makeEngine(minWords: 2, maxWords: 4, seed: seed)
            #expect(engine.isActive)
            #expect(engine.wordCount >= 2)
            #expect(engine.wordCount <= 4)
            #expect(Set(engine.words.map(\.word)).count == engine.wordCount)
            for word in engine.words {
                #expect(poolIDs.contains(word.word))
                #expect(word.image != nil)
                #expect(!word.sfx.isEmpty)
            }
        }
    }

    @Test func beginBuildsThreeDistinctChoicesWithOneCorrect() {
        let engine = makeEngine(seed: 7)
        #expect(engine.choices.count == PitBridgeMinigameEngine.choiceCount)
        let correct = engine.choices.filter(\.isCorrect)
        #expect(correct.count == 1)
        #expect(correct.first?.letter == engine.currentAnswer)
        #expect(Set(engine.choices.map(\.letter)).count == engine.choices.count)
    }

    @Test func everyRoundOffersDistinctChoiceLetters() {
        for position in [GateWordPlugLetterPosition.starting, .ending] {
            for seed in UInt64(1)...40 {
                var engine = makeEngine(minWords: 2, maxWords: 4, letterPosition: position, seed: seed)
                while engine.outcome == nil {
                    #expect(Set(engine.choices.map(\.letter)).count == engine.choices.count)
                    #expect(engine.choices.filter(\.isCorrect).count == 1)
                    guard let correct = engine.choices.first(where: \.isCorrect) else { break }
                    _ = engine.accept(choiceID: correct.id)
                }
            }
        }
    }

    @Test func currentRoundExposesCatalogImageAndSfx() {
        let sun = WordCatalog.imagedFallbackEntry(word: "sun")
        let engine = makeEngine(minWords: 1, maxWords: 1, words: [sun], seed: 1)
        #expect(engine.currentWord == "sun")
        #expect(engine.currentImageName == "sun")
        #expect(engine.currentSfx == "sfx_word_sun")
        #expect(engine.currentAnswer == "n")
        #expect(engine.maskedPromptText == "su_")
    }

    @Test func maskedPromptTextBlanksLastLetter() {
        let can = WordCatalog.imagedFallbackEntry(word: "can")
        let engine = makeEngine(minWords: 1, maxWords: 1, words: [can], seed: 1)
        #expect(engine.maskedPromptText == "ca_")
        #expect(engine.maskedPromptText.last == "_")
        #expect(String(engine.maskedPromptText.dropLast()) == String(engine.currentWord.dropLast()))
    }

    @Test func startingModeAnswersAndMasksFirstLetter() {
        let dog = WordCatalog.imagedFallbackEntry(word: "dog")
        let engine = makeEngine(
            minWords: 1,
            maxWords: 1,
            letterPosition: .starting,
            words: [dog],
            seed: 1
        )
        #expect(engine.currentAnswer == "d")
        #expect(engine.maskedPromptText == "_og")
        #expect(engine.choices.first(where: \.isCorrect)?.letter == "d")
    }

    @Test func digraphStartingMaskBlanksFullGraphemeSpan() {
        let stop = WordCatalog.imagedFallbackEntry(word: "stop", graphemes: ["st", "o", "p"])
        let engine = makeEngine(
            minWords: 1,
            maxWords: 1,
            letterPosition: .starting,
            words: [stop],
            seed: 1
        )
        #expect(engine.currentAnswer == "st")
        #expect(engine.maskedPromptText == "__op")
        #expect(engine.choices.first(where: \.isCorrect)?.letter == "st")
    }

    @Test func digraphEndingMaskBlanksFullGraphemeSpan() {
        let high = WordCatalog.imagedFallbackEntry(word: "high", graphemes: ["h", "igh"])
        let engine = makeEngine(
            minWords: 1,
            maxWords: 1,
            letterPosition: .ending,
            words: [high],
            seed: 1
        )
        #expect(engine.currentAnswer == "igh")
        #expect(engine.maskedPromptText == "h___")
        #expect(engine.choices.first(where: \.isCorrect)?.letter == "igh")
    }

    @Test func startingModeMasksFirstLetterAcrossPool() {
        for seed in UInt64(1)...UInt64(40) {
            let engine = makeEngine(
                minWords: 1,
                maxWords: 1,
                letterPosition: .starting,
                seed: seed
            )
            #expect(engine.maskedPromptText == "_\(engine.currentWord.dropFirst())")
            #expect(engine.currentAnswer == String(engine.currentWord.prefix(1)))
            #expect(engine.choices.first(where: \.isCorrect)?.letter == engine.currentAnswer)
        }
    }

    @Test func wrongAcceptLeavesStateUntouched() {
        var engine = makeEngine(seed: 3)
        guard let wrong = engine.choices.first(where: { !$0.isCorrect }) else {
            Issue.record("expected a wrong choice")
            return
        }
        let roundBefore = engine.roundIndex
        let choicesBefore = engine.choices
        #expect(engine.accept(choiceID: wrong.id) == .incorrect)
        #expect(engine.roundIndex == roundBefore)
        #expect(engine.choices == choicesBefore)
        #expect(engine.outcome == nil)
        #expect(!engine.isFrozen)
    }

    @Test func correctAcceptsAdvanceAndWinAfterN() {
        var engine = makeEngine(minWords: 2, maxWords: 2, seed: 11)
        let n = engine.wordCount
        #expect(n == 2)

        for index in 0..<n {
            guard let correct = engine.choices.first(where: { $0.isCorrect }) else {
                Issue.record("expected a correct choice at round \(index)")
                return
            }
            let result = engine.accept(choiceID: correct.id)
            let won = index == n - 1
            #expect(result == .correct(slotIndex: index, won: won))
            if won {
                #expect(engine.outcome == .won(starsAwarded: n))
                #expect(engine.isFrozen)
            } else {
                #expect(engine.outcome == nil)
                #expect(engine.choices.count == 3)
            }
        }
    }

    @Test func acceptReturnsNilBeforeBeginAfterEndAndAfterWin() {
        var engine = PitBridgeMinigameEngine(
            config: .init(
                minWords: 1,
                maxWords: 1,
                words: [WordCatalog.imagedFallbackEntry(word: "sun")]
            ),
            rng: PitSeededGenerator(seed: 2)
        )
        #expect(engine.accept(choiceID: UUID()) == nil)

        engine.begin()
        guard let correct = engine.choices.first(where: { $0.isCorrect }) else {
            Issue.record("expected a correct choice")
            return
        }
        #expect(engine.accept(choiceID: correct.id) == .correct(slotIndex: 0, won: true))
        #expect(engine.accept(choiceID: correct.id) == nil)

        var other = makeEngine(seed: 4)
        other.end()
        if let id = other.choices.first?.id {
            #expect(other.accept(choiceID: id) == nil)
        }
    }
}
