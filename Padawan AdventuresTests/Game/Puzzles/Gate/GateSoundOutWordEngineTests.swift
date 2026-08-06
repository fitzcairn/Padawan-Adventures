import Foundation
import Testing
@testable import Padawan_Adventures

struct GateSoundOutWordEngineTests {
    private func words(_ values: [String]) -> [GateWord] {
        values.map { GateWord.fallbackEntry(word: $0) }
    }

    private func graphemes(_ values: [String]) -> [GateGrapheme] {
        values.map {
            GateGrapheme(grapheme: $0, pronunciation: "sfx_letter_\($0)", name: "sfx_letter_\($0)_name")
        }
    }

    private let alphabet = "abcdefghijklmnopqrstuvwxyz".map(String.init)

    private func makeEngine(
        choiceCountMin: Int = 2,
        choiceCountMax: Int = 4,
        words: [String] = ["cat", "dog"],
        seed: UInt64 = 42
    ) -> GateSoundOutWordEngine {
        var engine = GateSoundOutWordEngine(
            config: .init(
                choiceCountMin: choiceCountMin,
                choiceCountMax: choiceCountMax,
                words: self.words(words),
                graphemes: graphemes(alphabet)
            ),
            rng: GateSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = GateSoundOutWordEngine(
            config: .init(words: words(["cat"]), graphemes: graphemes(alphabet))
        )
        #expect(!engine.isActive)
        #expect(engine.targetWord.isEmpty)
        #expect(engine.choiceSets.isEmpty)
        #expect(engine.currentIndex == nil)
        #expect(engine.currentChoices.isEmpty)
    }

    @Test func beginPicksWordAndBuildsOneChoiceSetPerGrapheme() {
        let engine = makeEngine(words: ["cat"], seed: 7)
        #expect(engine.isActive)
        #expect(engine.targetWord == "cat")
        #expect(engine.wordTrackID == "sfx_word_cat")
        #expect(engine.targetGraphemes == ["c", "a", "t"])
        #expect(engine.choiceSets.count == 3)
        #expect(engine.placedCount == 0)
        #expect(engine.currentIndex == 0)
        #expect(engine.currentGrapheme == "c")
    }

    @Test func everyChoiceSetHoldsTheAnswerPlusDistinctDecoys() {
        let engine = makeEngine(choiceCountMin: 3, choiceCountMax: 3, words: ["sat"], seed: 11)
        #expect(engine.choiceSets.count == 3)

        for (index, set) in engine.choiceSets.enumerated() {
            let answer = engine.grapheme(at: index)
            #expect(set.count == 3)
            #expect(set.contains { $0.grapheme == answer })
            #expect(Set(set.map(\.grapheme)).count == set.count)
            // Tints are what tell the blank faces apart, so they must be unique per set.
            #expect(Set(set.map(\.tintIndex)).count == set.count)
        }
    }

    @Test func choiceSetSizesStayInsideConfiguredRange() {
        let engine = makeEngine(choiceCountMin: 2, choiceCountMax: 4, words: ["map"], seed: 5)
        for set in engine.choiceSets {
            #expect(set.count >= 2)
            #expect(set.count <= 4)
        }
    }

    @Test func configClampsChoiceRangeToSupportedBounds() {
        let config = GateSoundOutWordEngine.Config(
            choiceCountMin: 0,
            choiceCountMax: 99,
            words: words(["cat"]),
            graphemes: graphemes(alphabet)
        )
        #expect(config.choiceCountMin == GateSoundOutWordConfig.minChoiceCount)
        #expect(config.choiceCountMax == GateSoundOutWordConfig.maxChoiceCount)
    }

    @Test func beginIsDeterministicForSeed() {
        let a = makeEngine(words: ["sat", "map", "can"], seed: 99)
        let b = makeEngine(words: ["sat", "map", "can"], seed: 99)
        #expect(a.targetWord == b.targetWord)
        #expect(a.wordTrackID == b.wordTrackID)
        #expect(a.choiceSets.map { $0.map(\.grapheme) } == b.choiceSets.map { $0.map(\.grapheme) })
    }

    @Test func graphemeTracksComeFromTheCatalog() {
        let engine = makeEngine(words: ["cat"], seed: 1)
        #expect(engine.nameTrackID(for: "c") == "sfx_letter_c_name")
        #expect(engine.soundTrackID(for: "c") == "sfx_letter_c")
        #expect(engine.nameTrackID(for: "?") == nil)
        #expect(engine.soundTrackID(for: "?") == nil)
    }

    @Test func correctChoiceInValidSpotAdvancesTheWord() throws {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let answer = try #require(engine.currentChoices.first { $0.grapheme == "c" })
        #expect(engine.drop(choiceID: answer.id, isPlacementValid: true) == .accepted)
        #expect(engine.placedCount == 1)
        #expect(engine.currentIndex == 1)
        #expect(engine.currentGrapheme == "a")
        #expect(engine.outcome == nil)
    }

    @Test func wrongChoiceIsRejectedAndKeepsTheSameGrapheme() throws {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let decoy = try #require(engine.currentChoices.first { $0.grapheme != "c" })
        #expect(engine.drop(choiceID: decoy.id, isPlacementValid: true) == .rejected)
        #expect(engine.placedCount == 0)
        #expect(engine.currentGrapheme == "c")
    }

    @Test func shuffleCurrentChoicesReordersWithoutLosingTheAnswer() throws {
        var engine = makeEngine(choiceCountMin: 3, choiceCountMax: 3, words: ["cat"], seed: 3)
        let beforeIDs = engine.currentChoices.map(\.id)
        let beforeGraphemes = Set(engine.currentChoices.map(\.grapheme))
        #expect(beforeIDs.count > 1)
        engine.shuffleCurrentChoices()
        #expect(Set(engine.currentChoices.map(\.id)) == Set(beforeIDs))
        #expect(Set(engine.currentChoices.map(\.grapheme)) == beforeGraphemes)
        #expect(engine.currentChoices.contains { $0.grapheme == "c" })
        // Same seed + forced reshuffle should move at least one slot when n > 1.
        #expect(engine.currentChoices.map(\.id) != beforeIDs)
    }

    @Test func correctChoiceInInvalidSpotIsRejected() throws {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let answer = try #require(engine.currentChoices.first { $0.grapheme == "c" })
        #expect(engine.drop(choiceID: answer.id, isPlacementValid: false) == .rejected)
        #expect(engine.placedCount == 0)
        #expect(engine.currentGrapheme == "c")
    }

    @Test func choiceFromAnotherSetIsRejected() {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let laterChoice = engine.choiceSets[2][0]
        #expect(engine.drop(choiceID: laterChoice.id, isPlacementValid: true) == .rejected)
        #expect(engine.placedCount == 0)
    }

    @Test func completingTheWordWinsWithOneStarPerGrapheme() throws {
        var engine = makeEngine(words: ["cat"], seed: 1)
        for expected in ["c", "a", "t"] {
            let answer = try #require(engine.currentChoices.first { $0.grapheme == expected })
            #expect(engine.drop(choiceID: answer.id, isPlacementValid: true) == .accepted)
        }
        #expect(engine.isSolved)
        #expect(engine.currentIndex == nil)
        #expect(engine.currentChoices.isEmpty)
        #expect(engine.outcome == .won(starsAwarded: 3))
    }

    @Test func dropsAfterWinningAreIgnored() throws {
        var engine = makeEngine(words: ["cat"], seed: 1)
        for expected in ["c", "a", "t"] {
            let answer = try #require(engine.currentChoices.first { $0.grapheme == expected })
            engine.drop(choiceID: answer.id, isPlacementValid: true)
        }
        let stale = engine.choiceSets[0][0]
        #expect(engine.drop(choiceID: stale.id, isPlacementValid: true) == .rejected)
        #expect(engine.placedCount == 3)
    }

    @Test func dropBeforeBeginIsRejected() {
        var engine = GateSoundOutWordEngine(
            config: .init(words: words(["cat"]), graphemes: graphemes(alphabet))
        )
        #expect(engine.drop(choiceID: UUID(), isPlacementValid: true) == .rejected)
    }
}

/// Deterministic RNG for gate puzzle tests.
struct GateSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
