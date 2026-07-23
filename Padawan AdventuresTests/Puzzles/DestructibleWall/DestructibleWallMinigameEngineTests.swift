import Foundation
import Testing
@testable import Padawan_Adventures

struct DestructibleWallMinigameEngineTests {
    private func letters(_ values: [String]) -> [DestructibleWallLetter] {
        values.map {
            DestructibleWallLetter(
                letter: $0,
                pronunciation: "sfx_letter_\($0)_pronunciation",
                name: "sfx_letter_\($0)_name"
            )
        }
    }

    private func makeEngine(
        timer: Double = 30,
        letterCountMin: Int = 2,
        letterCountMax: Int = 4,
        pool: [String] = ["a", "b", "c", "d", "e", "f", "g", "h"],
        seed: UInt64 = 42
    ) -> DestructibleWallMinigameEngine {
        var engine = DestructibleWallMinigameEngine(
            config: .init(
                timerSeconds: timer,
                letterCountMin: letterCountMin,
                letterCountMax: letterCountMax,
                letters: letters(pool)
            ),
            rng: GateSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = DestructibleWallMinigameEngine(
            config: .init(timerSeconds: 30, letters: letters(["a"]))
        )
        #expect(!engine.isActive)
        #expect(engine.letters.isEmpty)
        #expect(engine.currentTargetID == nil)
    }

    @Test func beginPicksLettersAndTarget() {
        let engine = makeEngine(letterCountMin: 2, letterCountMax: 4, seed: 7)
        #expect(engine.isActive)
        #expect(engine.letters.count >= 2)
        #expect(engine.letters.count <= 4)
        #expect(engine.currentTargetID != nil)
        #expect(!engine.targetPronunciationTrackID.isEmpty)
    }

    @Test func beginIsDeterministicForSeed() {
        let a = makeEngine(letterCountMin: 2, letterCountMax: 4, seed: 99)
        let b = makeEngine(letterCountMin: 2, letterCountMax: 4, seed: 99)
        #expect(a.letters.map(\.letter) == b.letters.map(\.letter))
        #expect(a.currentTarget?.letter == b.currentTarget?.letter)
    }

    @Test func letterCountMinMaxEqualSelectsExactCount() {
        let engine = makeEngine(
            letterCountMin: 1,
            letterCountMax: 1,
            pool: ["a", "b", "c"],
            seed: 1
        )
        #expect(engine.letters.count == 1)
    }

    @Test func letterCountRangeClampedToPoolSize() {
        let engine = makeEngine(
            letterCountMin: 3,
            letterCountMax: 5,
            pool: ["a", "b", "c"],
            seed: 2
        )
        #expect(engine.letters.count == 3)
    }

    @Test func letterCountStaysWithinConfiguredRange() {
        for seed in UInt64(1)...40 {
            let engine = makeEngine(
                letterCountMin: 2,
                letterCountMax: 4,
                pool: ["a", "b", "c", "d", "e", "f"],
                seed: seed
            )
            #expect(engine.letters.count >= 2)
            #expect(engine.letters.count <= 4)
        }
    }

    @Test func correctTapGreensAndAdvancesTowardWin() {
        var engine = makeEngine(
            letterCountMin: 2,
            letterCountMax: 2,
            pool: ["a", "b"],
            seed: 5
        )
        #expect(engine.letters.count == 2)
        guard let firstTarget = engine.currentTarget else {
            Issue.record("expected a target")
            return
        }

        let events = engine.tapLetter(id: firstTarget.id)
        #expect(events.contains(DestructibleWallEngineEvent.playName(trackID: firstTarget.nameTrackID)))
        #expect(events.contains(DestructibleWallEngineEvent.correctMatch(id: firstTarget.id)))
        #expect(events.contains(DestructibleWallEngineEvent.playYay))
        #expect(events.contains(DestructibleWallEngineEvent.playTargetPronunciation))
        #expect(engine.matchedIDs.contains(firstTarget.id))
        #expect(!events.contains(DestructibleWallEngineEvent.won))
        #expect(engine.currentTargetID != firstTarget.id)

        guard let secondTarget = engine.currentTarget else {
            Issue.record("expected a second target")
            return
        }
        let winEvents = engine.tapLetter(id: secondTarget.id)
        #expect(winEvents.contains(DestructibleWallEngineEvent.won))
        #expect(!winEvents.contains(DestructibleWallEngineEvent.playTargetPronunciation))
        #expect(engine.outcome == .won(starsAwarded: 2))
        #expect(engine.isFrozen)
    }

    @Test func incorrectTapDoesNotAutoReplayTarget() {
        var engine = makeEngine(
            letterCountMin: 2,
            letterCountMax: 2,
            pool: ["a", "b"],
            seed: 5
        )
        guard let target = engine.currentTarget,
              let wrong = engine.letters.first(where: { $0.id != target.id }) else {
            Issue.record("expected target and wrong letter")
            return
        }

        let events = engine.tapLetter(id: wrong.id)
        #expect(events.contains(DestructibleWallEngineEvent.playName(trackID: wrong.nameTrackID)))
        #expect(
            events.contains(
                DestructibleWallEngineEvent.incorrectMatch(
                    id: wrong.id,
                    pronunciationTrackID: wrong.pronunciationTrackID
                )
            )
        )
        #expect(!events.contains(DestructibleWallEngineEvent.playTargetPronunciation))
        #expect(engine.matchedIDs.isEmpty)
        #expect(engine.currentTargetID == target.id)

        let later = engine.tick(dt: 5.0)
        #expect(!later.contains(DestructibleWallEngineEvent.playTargetPronunciation))
    }

    @Test func tickNeverAutoReplaysTargetPronunciation() {
        var engine = makeEngine(
            letterCountMin: 1,
            letterCountMax: 1,
            pool: ["a"],
            seed: 1
        )
        let events = engine.tick(dt: 30)
        #expect(!events.contains(DestructibleWallEngineEvent.playTargetPronunciation))
    }

    @Test func timerExpiryProducesLostAndUrgentTicks() {
        var engine = makeEngine(
            timer: 3,
            letterCountMin: 1,
            letterCountMax: 1,
            pool: ["a"],
            seed: 1
        )
        var ticks = 0
        for _ in 0..<3 {
            let events = engine.tick(dt: 1.0)
            ticks += events.filter { $0 == DestructibleWallEngineEvent.timerTick }.count
        }
        #expect(ticks >= 1)
        #expect(engine.outcome == .lost)
        #expect(engine.isFrozen)
        #expect(engine.tick(dt: 0.5).isEmpty)
    }

    @Test func tapIgnoredAfterFrozen() {
        var engine = makeEngine(
            timer: 1,
            letterCountMin: 1,
            letterCountMax: 1,
            pool: ["a"],
            seed: 1
        )
        _ = engine.tick(dt: 1.1)
        #expect(engine.outcome == .lost)
        guard let target = engine.letters.first else { return }
        #expect(engine.tapLetter(id: target.id).isEmpty)
    }

    @Test func matchedLetterCannotBeTappedAgain() {
        var engine = makeEngine(
            letterCountMin: 2,
            letterCountMax: 2,
            pool: ["a", "b"],
            seed: 5
        )
        guard let first = engine.currentTarget else { return }
        _ = engine.tapLetter(id: first.id)
        #expect(engine.tapLetter(id: first.id).isEmpty)
    }
}
