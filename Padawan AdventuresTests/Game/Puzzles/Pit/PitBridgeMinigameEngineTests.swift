import Foundation
import Testing
@testable import Padawan_Adventures

struct PitBridgeMinigameEngineTests {
    private let poolIDs = ["car", "dog", "trash", "sun", "star", "book"]

    private var pool: [GateWord] {
        poolIDs.map { WordCatalog.imagedFallbackEntry(word: $0) }
    }

    private func makeEngine(
        minWords: Int = 2,
        maxWords: Int = 4,
        words: [GateWord]? = nil,
        seed: UInt64 = 42
    ) -> PitBridgeMinigameEngine {
        var engine = PitBridgeMinigameEngine(
            config: .init(
                minWords: minWords,
                maxWords: maxWords,
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

    @Test func currentRoundExposesCatalogImageAndSfx() {
        let sun = WordCatalog.imagedFallbackEntry(word: "sun")
        let engine = makeEngine(minWords: 1, maxWords: 1, words: [sun], seed: 1)
        #expect(engine.currentWord == "sun")
        #expect(engine.currentImageName == "sun")
        #expect(engine.currentSfx == "sfx_word_sun")
        #expect(engine.currentAnswer == "n")
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
