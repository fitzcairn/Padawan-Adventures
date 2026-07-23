import Foundation
import Testing
@testable import Padawan_Adventures

struct GateMinigameEngineTests {
    private func words(_ values: [String]) -> [GateWord] {
        values.map { GateWord(word: $0, sound: "sfx_word_\($0)") }
    }

    private func makeEngine(
        timer: Double = 30,
        wordSoundRepeatSeconds: Double = 10,
        numPaddingLetters: Int = 6,
        words: [String] = ["cat", "dog"],
        seed: UInt64 = 42
    ) -> GateMinigameEngine {
        var engine = GateMinigameEngine(
            config: .init(
                timerSeconds: timer,
                wordSoundRepeatSeconds: wordSoundRepeatSeconds,
                numPaddingLetters: numPaddingLetters,
                words: self.words(words)
            ),
            rng: GateSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = GateMinigameEngine(
            config: .init(timerSeconds: 30, words: words(["cat"]))
        )
        #expect(!engine.isActive)
        #expect(engine.letters.isEmpty)
        #expect(engine.targetWord.isEmpty)
        #expect(engine.targetSoundTrackID.isEmpty)
    }

    @Test func beginPicksWordAndBuildsPaddedLetterBag() {
        let engine = makeEngine(numPaddingLetters: 6, words: ["cat"], seed: 7)
        #expect(engine.isActive)
        #expect(engine.targetWord == "cat")
        #expect(engine.targetSoundTrackID == "sfx_word_cat")
        #expect(engine.letters.count == 9) // 3 letters + 6 padding

        let letterCounts = Dictionary(grouping: engine.letters, by: \.letter).mapValues(\.count)
        #expect((letterCounts["c"] ?? 0) >= 1)
        #expect((letterCounts["a"] ?? 0) >= 1)
        #expect((letterCounts["t"] ?? 0) >= 1)
    }

    @Test func letterBagSizeUsesConfiguredPadding() {
        let engine = makeEngine(numPaddingLetters: 2, words: ["star"], seed: 3)
        #expect(engine.targetWord == "star")
        #expect(engine.letters.count == 6) // 4 + 2
    }

    @Test func beginIsDeterministicForSeed() {
        let a = makeEngine(words: ["star", "gate", "open"], seed: 99)
        let b = makeEngine(words: ["star", "gate", "open"], seed: 99)
        #expect(a.targetWord == b.targetWord)
        #expect(a.targetSoundTrackID == b.targetSoundTrackID)
        #expect(a.letters.map(\.letter) == b.letters.map(\.letter))
    }

    @Test func stagingExactWordWinsAwardsOneStarPerLetter() {
        var engine = makeEngine(words: ["cat"], seed: 1)
        #expect(engine.targetWord == "cat")
        let won = engine.evaluateStaging(orderedLetters: ["c", "a", "t"])
        #expect(won)
        #expect(engine.outcome == .won(starsAwarded: 3))
        #expect(engine.isFrozen)
    }

    @Test func stagingWrongOrderDoesNotWin() {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let won = engine.evaluateStaging(orderedLetters: ["t", "a", "c"])
        #expect(!won)
        #expect(engine.outcome == nil)
        #expect(!engine.isFrozen)
    }

    @Test func stagingExtraLettersDoesNotWin() {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let won = engine.evaluateStaging(orderedLetters: ["c", "a", "t", "x"])
        #expect(!won)
        #expect(engine.outcome == nil)
    }

    @Test func stagingMissingLettersDoesNotWin() {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let won = engine.evaluateStaging(orderedLetters: ["c", "a"])
        #expect(!won)
        #expect(engine.outcome == nil)
    }

    @Test func timerExpiryProducesLostAndUrgentTicks() {
        var engine = makeEngine(timer: 3, words: ["cat"], seed: 1)
        var ticks = 0
        for _ in 0..<3 {
            let events = engine.tick(dt: 1.0)
            ticks += events.filter { $0 == .timerTick }.count
        }
        #expect(ticks >= 1)
        #expect(engine.outcome == .lost)
        #expect(engine.isFrozen)
        #expect(engine.tick(dt: 0.5).isEmpty)
    }

    @Test func evaluateIgnoredAfterFrozen() {
        var engine = makeEngine(timer: 1, words: ["cat"], seed: 1)
        _ = engine.tick(dt: 1.1)
        #expect(engine.outcome == .lost)
        let won = engine.evaluateStaging(orderedLetters: ["c", "a", "t"])
        #expect(!won)
    }

    @Test func autoPlaysWordSoundAfterRepeatInterval() {
        var engine = makeEngine(
            timer: 30,
            wordSoundRepeatSeconds: 10,
            words: ["cat"],
            seed: 1
        )
        engine.markWordSoundPlayed()

        let early = engine.tick(dt: 9.0)
        #expect(!early.contains(.playWordSound))

        let due = engine.tick(dt: 1.1)
        #expect(due.contains(.playWordSound))
    }

    @Test func markWordSoundPlayedDelaysNextAutoPlay() {
        var engine = makeEngine(
            timer: 30,
            wordSoundRepeatSeconds: 5,
            words: ["cat"],
            seed: 1
        )
        engine.markWordSoundPlayed()
        _ = engine.tick(dt: 4.0)
        engine.markWordSoundPlayed()

        let stillEarly = engine.tick(dt: 4.0)
        #expect(!stillEarly.contains(.playWordSound))

        let due = engine.tick(dt: 1.5)
        #expect(due.contains(.playWordSound))
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
