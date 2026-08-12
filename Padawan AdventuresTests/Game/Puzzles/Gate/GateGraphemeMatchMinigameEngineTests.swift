import Foundation
import Testing
@testable import Padawan_Adventures

struct GateGraphemeMatchMinigameEngineTests {
    private func letters(_ values: [String]) -> [GateGrapheme] {
        values.map {
            GateGrapheme(
                grapheme: $0,
                pronunciation: "sfx_letter_\($0)_pronunciation",
                name: "sfx_letter_\($0)_name"
            )
        }
    }

    private func makeEngine(
        graphemeCountMin: Int = 2,
        graphemeCountMax: Int = 4,
        pool: [String] = ["a", "b", "c", "d", "e", "f", "g", "h"],
        seed: UInt64 = 42
    ) -> GateGraphemeMatchMinigameEngine {
        var engine = GateGraphemeMatchMinigameEngine(
            config: .init(
                graphemeCountMin: graphemeCountMin,
                graphemeCountMax: graphemeCountMax,
                graphemes: letters(pool)
            ),
            rng: SeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = GateGraphemeMatchMinigameEngine(
            config: .init(graphemes: letters(["a"]))
        )
        #expect(!engine.isActive)
        #expect(engine.letters.isEmpty)
        #expect(engine.currentTargetID == nil)
    }

    @Test func beginPicksLettersAndTarget() {
        let engine = makeEngine(graphemeCountMin: 2, graphemeCountMax: 4, seed: 7)
        #expect(engine.isActive)
        #expect(engine.letters.count >= 2)
        #expect(engine.letters.count <= 4)
        #expect(engine.currentTargetID != nil)
        #expect(!engine.targetPronunciationTrackID.isEmpty)
    }

    @Test func beginIsDeterministicForSeed() {
        let a = makeEngine(graphemeCountMin: 2, graphemeCountMax: 4, seed: 99)
        let b = makeEngine(graphemeCountMin: 2, graphemeCountMax: 4, seed: 99)
        #expect(a.letters.map(\.letter) == b.letters.map(\.letter))
        #expect(a.currentTarget?.letter == b.currentTarget?.letter)
    }

    @Test func graphemeCountMinMaxEqualSelectsExactCount() {
        let engine = makeEngine(
            graphemeCountMin: 1,
            graphemeCountMax: 1,
            pool: ["a", "b", "c"],
            seed: 1
        )
        #expect(engine.letters.count == 1)
    }

    @Test func letterCountRangeClampedToPoolSize() {
        let engine = makeEngine(
            graphemeCountMin: 3,
            graphemeCountMax: 5,
            pool: ["a", "b", "c"],
            seed: 2
        )
        #expect(engine.letters.count == 3)
    }

    @Test func letterCountStaysWithinConfiguredRange() {
        for seed in UInt64(1)...40 {
            let engine = makeEngine(
                graphemeCountMin: 2,
                graphemeCountMax: 4,
                pool: ["a", "b", "c", "d", "e", "f"],
                seed: seed
            )
            #expect(engine.letters.count >= 2)
            #expect(engine.letters.count <= 4)
        }
    }

    @Test func lowerGraphemeCaseRendersLowercaseLetters() {
        var engine = GateGraphemeMatchMinigameEngine(
            config: .init(
                graphemeCountMin: 3,
                graphemeCountMax: 3,
                graphemeCase: .lower,
                graphemes: letters(["a", "b", "c"])
            ),
            rng: SeededGenerator(seed: 3)
        )
        engine.begin()
        #expect(engine.letters.map(\.letter) == engine.letters.map { $0.letter.lowercased() })
        #expect(Set(engine.letters.map(\.letter)).isSubset(of: ["a", "b", "c"]))
    }

    @Test func upperGraphemeCaseRendersUppercaseLetters() {
        var engine = GateGraphemeMatchMinigameEngine(
            config: .init(
                graphemeCountMin: 3,
                graphemeCountMax: 3,
                graphemeCase: .upper,
                graphemes: letters(["a", "b", "c"])
            ),
            rng: SeededGenerator(seed: 3)
        )
        engine.begin()
        #expect(engine.letters.map(\.letter) == engine.letters.map { $0.letter.uppercased() })
        #expect(Set(engine.letters.map(\.letter)).isSubset(of: ["A", "B", "C"]))
    }

    @Test func bothGraphemeCaseMixesLetterCaseAcrossSeeds() {
        var sawLower = false
        var sawUpper = false
        for seed in UInt64(1)...40 {
            var engine = GateGraphemeMatchMinigameEngine(
                config: .init(
                    graphemeCountMin: 3,
                    graphemeCountMax: 3,
                    graphemeCase: .both,
                    graphemes: letters(["a", "b", "c"])
                ),
                rng: SeededGenerator(seed: seed)
            )
            engine.begin()
            for letter in engine.letters.map(\.letter) {
                if letter == letter.lowercased() { sawLower = true }
                if letter == letter.uppercased() { sawUpper = true }
            }
        }
        #expect(sawLower)
        #expect(sawUpper)
    }

    @Test func correctTapGreensAndAdvancesTowardWin() {
        var engine = makeEngine(
            graphemeCountMin: 2,
            graphemeCountMax: 2,
            pool: ["a", "b"],
            seed: 5
        )
        #expect(engine.letters.count == 2)
        guard let firstTarget = engine.currentTarget else {
            Issue.record("expected a target")
            return
        }

        let events = engine.tapLetter(id: firstTarget.id)
        #expect(events.contains(GateGraphemeMatchEngineEvent.playName(trackID: firstTarget.nameTrackID)))
        #expect(events.contains(GateGraphemeMatchEngineEvent.correctMatch(id: firstTarget.id)))
        #expect(events.contains(GateGraphemeMatchEngineEvent.playYay))
        #expect(events.contains(GateGraphemeMatchEngineEvent.playTargetPronunciation))
        #expect(engine.matchedIDs.contains(firstTarget.id))
        #expect(!events.contains(GateGraphemeMatchEngineEvent.won))
        #expect(engine.currentTargetID != firstTarget.id)

        guard let secondTarget = engine.currentTarget else {
            Issue.record("expected a second target")
            return
        }
        let winEvents = engine.tapLetter(id: secondTarget.id)
        #expect(winEvents.contains(GateGraphemeMatchEngineEvent.won))
        #expect(!winEvents.contains(GateGraphemeMatchEngineEvent.playTargetPronunciation))
        #expect(engine.outcome == .won(starsAwarded: 2))
        #expect(engine.isFrozen)
    }

    @Test func incorrectTapDoesNotAutoReplayTarget() {
        var engine = makeEngine(
            graphemeCountMin: 2,
            graphemeCountMax: 2,
            pool: ["a", "b"],
            seed: 5
        )
        guard let target = engine.currentTarget,
              let wrong = engine.letters.first(where: { $0.id != target.id }) else {
            Issue.record("expected target and wrong letter")
            return
        }

        let events = engine.tapLetter(id: wrong.id)
        #expect(events.contains(GateGraphemeMatchEngineEvent.playName(trackID: wrong.nameTrackID)))
        #expect(
            events.contains(
                GateGraphemeMatchEngineEvent.incorrectMatch(
                    id: wrong.id,
                    pronunciationTrackID: wrong.pronunciationTrackID
                )
            )
        )
        #expect(!events.contains(GateGraphemeMatchEngineEvent.playTargetPronunciation))
        #expect(engine.matchedIDs.isEmpty)
        #expect(engine.currentTargetID == target.id)
    }

    @Test func tapIgnoredAfterFrozen() {
        var engine = makeEngine(
            graphemeCountMin: 1,
            graphemeCountMax: 1,
            pool: ["a"],
            seed: 1
        )
        guard let target = engine.letters.first else { return }
        _ = engine.tapLetter(id: target.id)
        #expect(engine.outcome == .won(starsAwarded: 1))
        #expect(engine.tapLetter(id: target.id).isEmpty)
    }

    @Test func matchedLetterCannotBeTappedAgain() {
        var engine = makeEngine(
            graphemeCountMin: 2,
            graphemeCountMax: 2,
            pool: ["a", "b"],
            seed: 5
        )
        guard let first = engine.currentTarget else { return }
        _ = engine.tapLetter(id: first.id)
        #expect(engine.tapLetter(id: first.id).isEmpty)
    }
}
