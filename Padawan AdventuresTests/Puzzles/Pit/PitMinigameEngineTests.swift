import Foundation
import Testing
@testable import Padawan_Adventures

struct PitMinigameEngineTests {
    private func words(_ values: [String]) -> [GateWord] {
        values.map { GateWord.fallbackEntry(word: $0) }
    }

    private func makeEngine(
        timer: Double = 30,
        words: [String] = ["cat", "dog"],
        seed: UInt64 = 42
    ) -> PitMinigameEngine {
        var engine = PitMinigameEngine(
            config: .init(
                timerSeconds: timer,
                words: self.words(words)
            ),
            rng: PitSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = PitMinigameEngine(
            config: .init(timerSeconds: 30, words: words(["cat"]))
        )
        #expect(!engine.isActive)
        #expect(engine.letters.isEmpty)
        #expect(engine.targetWord.isEmpty)
    }

    @Test func beginPicksWordAndBuildsMultisetPlusDecoys() {
        let engine = makeEngine(words: ["cat"], seed: 7)
        #expect(engine.isActive)
        #expect(engine.targetWord == "cat")
        #expect(engine.targetSoundTrackID == "sfx_word_cat")
        #expect(engine.wordLetterIDs.count == 3)
        #expect(engine.letters.count >= 4)
        #expect(engine.letters.count <= 6)

        let letterCounts = Dictionary(grouping: engine.letters, by: \.letter).mapValues(\.count)
        #expect((letterCounts["c"] ?? 0) >= 1)
        #expect((letterCounts["a"] ?? 0) >= 1)
        #expect((letterCounts["t"] ?? 0) >= 1)
    }

    @Test func decoyCountIsBetweenOneAndUniqueSetSize() {
        let engine = makeEngine(words: ["book"], seed: 11)
        #expect(engine.targetWord == "book")
        #expect(engine.wordLetterIDs.count == 4)
        let decoyCount = engine.letters.count - engine.wordLetterIDs.count
        #expect(decoyCount >= 1)
        #expect(decoyCount <= 3) // unique set {b,o,k}
    }

    @Test func beginIsDeterministicForSeed() {
        let a = makeEngine(words: ["star", "cat", "dog"], seed: 99)
        let b = makeEngine(words: ["star", "cat", "dog"], seed: 99)
        #expect(a.targetWord == b.targetWord)
        #expect(a.letters.map(\.letter) == b.letters.map(\.letter))
        #expect(a.wordLetterIDs.count == b.wordLetterIDs.count)
    }

    @Test func correctLettersInOrderWinAndAwardStars() {
        var engine = makeEngine(words: ["cat"], seed: 1)
        #expect(engine.targetWord == "cat")
        #expect(engine.wordLetterIDs.count == 3)

        let first = engine.acceptLetter(id: engine.wordLetterIDs[0])
        #expect(first == .correct(prefix: "c", won: false))
        let second = engine.acceptLetter(id: engine.wordLetterIDs[1])
        #expect(second == .correct(prefix: "ca", won: false))
        let third = engine.acceptLetter(id: engine.wordLetterIDs[2])
        #expect(third == .correct(prefix: "cat", won: true))

        #expect(engine.outcome == .won(starsAwarded: 3))
        #expect(engine.isFrozen)
    }

    @Test func incorrectLetterDoesNotAdvance() {
        var engine = makeEngine(words: ["cat"], seed: 1)
        let decoy = engine.letters.first { token in
            !engine.wordLetterIDs.contains(token.id)
        }
        #expect(decoy != nil)
        guard let decoy else { return }

        let result = engine.acceptLetter(id: decoy.id)
        #expect(result == .incorrect)
        #expect(engine.nextLetterIndex == 0)
        #expect(engine.outcome == nil)
        #expect(!engine.isSpent(decoy.id))
    }

    @Test func spentCorrectLetterCannotBeReused() {
        var engine = makeEngine(words: ["book"], seed: 3)
        #expect(engine.targetWord == "book")
        let firstO = engine.wordLetterIDs
            .compactMap { engine.letter(id: $0) }
            .first { $0.letter == "b" }
        #expect(firstO != nil)
        guard let b = firstO else { return }
        #expect(engine.acceptLetter(id: b.id) == .correct(prefix: "b", won: false))
        #expect(engine.acceptLetter(id: b.id) == nil)
    }

    @Test func timerTickEmitsInLastFiveSeconds() {
        var engine = makeEngine(timer: 6, words: ["cat"], seed: 2)
        var sawTick = false
        // Advance past whole-second boundaries into the urgent window.
        for _ in 0..<70 {
            let events = engine.tick(dt: 0.1)
            if events.contains(.timerTick) {
                sawTick = true
            }
            if events.contains(.lost) { break }
        }
        #expect(sawTick)
        #expect(engine.outcome == .lost)
        #expect(engine.isFrozen)
    }

    @Test func tickDoesNotProgressWhenFrozen() {
        var engine = makeEngine(timer: 5, words: ["cat"], seed: 1)
        _ = engine.tick(dt: 10)
        #expect(engine.outcome == .lost)
        let remaining = engine.remainingTime
        _ = engine.tick(dt: 1)
        #expect(engine.remainingTime == remaining)
    }
}

struct PitSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
