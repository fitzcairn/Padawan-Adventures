import Foundation
import Testing
@testable import Padawan_Adventures

struct GateWordPlugMinigameEngineTests {
    private func letters(_ values: [String]) -> [GateLetter] {
        values.map {
            GateLetter(
                letter: $0,
                pronunciation: "sfx_letter_\($0)_pronunciation",
                name: "sfx_letter_\($0)_name"
            )
        }
    }

    private func words(_ values: [String]) -> [GateWord] {
        values.map { GateWord.fallbackEntry(word: $0) }
    }

    private func makeEngine(
        wordCountMin: Int = 3,
        wordCountMax: Int = 6,
        pool: [String] = ["cat", "dog", "star", "gate", "car"],
        letterPool: [String] = ["a", "b", "c", "d", "e", "f", "g", "h", "o", "s"],
        seed: UInt64 = 42
    ) -> GateWordPlugMinigameEngine {
        var engine = GateWordPlugMinigameEngine(
            config: .init(
                wordCountMin: wordCountMin,
                wordCountMax: wordCountMax,
                words: words(pool),
                letters: letters(letterPool)
            ),
            rng: SeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = GateWordPlugMinigameEngine(
            config: .init(words: words(["cat"]), letters: letters(["c"]))
        )
        #expect(!engine.isActive)
        #expect(engine.slots.isEmpty)
        #expect(engine.tray.isEmpty)
    }

    @Test func beginSnapsToMultipleOfThreeWhenAvailableInRange() {
        for seed in UInt64(1)...40 {
            let engine = makeEngine(
                wordCountMin: 3,
                wordCountMax: 6,
                pool: ["cat", "dog", "star", "gate", "car"],
                seed: seed
            )
            // Pool has 5 unique first letters; range snaps to 3.
            #expect(engine.slots.count == 3)
        }
    }

    @Test func beginKeepsCountWhenNoMultipleOfThreeInRange() {
        for seed in UInt64(1)...20 {
            let engine = makeEngine(
                wordCountMin: 2,
                wordCountMax: 2,
                pool: ["cat", "dog", "star", "gate", "car"],
                seed: seed
            )
            #expect(engine.slots.count == 2)
        }
    }

    @Test func beginIsDeterministicForSeed() {
        let a = makeEngine(seed: 99)
        let b = makeEngine(seed: 99)
        #expect(a.slots.map(\.word) == b.slots.map(\.word))
        #expect(a.tray.map(\.letter) == b.tray.map(\.letter))
    }

    @Test func beginCanPickEveryWordInThePool() {
        let pool = ["bath", "book", "cat", "dance", "dog", "lightbulb", "star", "wand"]
        var seen: Set<String> = []
        for seed in UInt64(1)...60 {
            let engine = makeEngine(
                wordCountMin: 2,
                wordCountMax: 2,
                pool: pool,
                letterPool: ["b", "c", "d", "l", "s", "w"],
                seed: seed
            )
            #expect(engine.slots.count == 2)
            seen.formUnion(engine.slots.map(\.word))
        }
        #expect(seen == Set(pool))
    }

    @Test func roundMayContainTwoWordsSharingAFirstLetter() {
        let engine = makeEngine(
            wordCountMin: 2,
            wordCountMax: 2,
            pool: ["bath", "book"],
            letterPool: ["b"],
            seed: 7
        )
        #expect(engine.slots.map(\.word).sorted() == ["bath", "book"])
        #expect(engine.tray.map(\.letter) == ["b", "b"])
    }

    @Test func maskedTextReplacesFirstLetter() {
        let engine = makeEngine(seed: 7)
        for slot in engine.slots {
            #expect(slot.maskedText == "_\(slot.word.dropFirst())")
            #expect(slot.maskedText.first == "_")
        }
    }

    @Test func trayHasOneTokenPerSlotWithMatchingLetters() {
        let engine = makeEngine(seed: 11)
        #expect(engine.tray.count == engine.slots.count)
        #expect(
            engine.tray.map(\.letter).sorted() == engine.slots.map(\.letter).sorted()
        )
    }

    @Test func tapLetterPlaysPronunciation() {
        var engine = makeEngine(seed: 3)
        guard let token = engine.tray.first else {
            Issue.record("expected tray token")
            return
        }
        let events = engine.tapLetter(id: token.id)
        #expect(events == [
            .playLetterSound(trackID: token.pronunciationTrackID),
        ])
    }

    @Test func tapWordPlaysWordTrack() {
        var engine = makeEngine(seed: 3)
        guard let slot = engine.slots.first else {
            Issue.record("expected slot")
            return
        }
        let events = engine.tapWord(slotID: slot.id)
        #expect(events == [.playWordSound(trackID: "sfx_word_\(slot.word)")])
    }

    @Test func correctPlugEmitsFlashAndCorrect() {
        var engine = makeEngine(
            wordCountMin: 3,
            wordCountMax: 3,
            pool: ["cat", "dog", "star"],
            seed: 1
        )
        guard let slot = engine.slots.first(where: { $0.word == "cat" }),
              let token = engine.tray.first(where: { $0.letter == "c" }) else {
            Issue.record("expected cat slot and c token")
            return
        }
        let events = engine.plug(letterID: token.id, intoSlotID: slot.id)
        #expect(events == [
            .correctPlug(slotID: slot.id, letterID: token.id),
            .playWordSound(trackID: "sfx_word_cat"),
            .playCorrect,
        ])
        #expect(engine.isSlotFilled(slot.id))
    }

    @Test func incorrectPlugEmitsOnlyIncorrect() {
        var engine = makeEngine(
            wordCountMin: 3,
            wordCountMax: 3,
            pool: ["cat", "dog", "star"],
            seed: 1
        )
        guard let slot = engine.slots.first(where: { $0.word == "cat" }),
              let token = engine.tray.first(where: { $0.letter == "d" }) else {
            Issue.record("expected cat slot and d token")
            return
        }
        let events = engine.plug(letterID: token.id, intoSlotID: slot.id)
        #expect(events == [.incorrectPlug(letterID: token.id)])
        #expect(!engine.isSlotFilled(slot.id))
    }

    @Test func pluggingEverySlotWinsAndAwardsStars() {
        for (minCount, maxCount, pool) in [
            (3, 3, ["cat", "dog", "star"]),
            (6, 6, ["cat", "dog", "star", "gate", "car", "sun"]),
        ] as [(Int, Int, [String])] {
            var engine = makeEngine(
                wordCountMin: minCount,
                wordCountMax: maxCount,
                pool: pool,
                seed: 5
            )
            #expect(engine.slots.count == maxCount)
            for slot in engine.slots {
                guard let token = engine.tray.first(where: {
                    $0.letter == slot.letter && !engine.isTokenPlugged($0.id)
                }) else {
                    Issue.record("missing token for \(slot.letter)")
                    return
                }
                _ = engine.plug(letterID: token.id, intoSlotID: slot.id)
            }
            #expect(engine.outcome == .won(starsAwarded: maxCount))
            #expect(engine.isFrozen)
        }
    }

    @Test func plugIsIgnoredAfterWin() {
        var engine = makeEngine(
            wordCountMin: 3,
            wordCountMax: 3,
            pool: ["cat", "dog", "star"],
            seed: 5
        )
        for slot in engine.slots {
            guard let token = engine.tray.first(where: {
                $0.letter == slot.letter && !engine.isTokenPlugged($0.id)
            }) else { continue }
            _ = engine.plug(letterID: token.id, intoSlotID: slot.id)
        }
        #expect(engine.outcome != nil)
        let events = engine.plug(
            letterID: engine.tray[0].id,
            intoSlotID: engine.slots[0].id
        )
        #expect(events.isEmpty)
    }

    @Test func plugIsIgnoredForFilledSocket() {
        var engine = makeEngine(
            wordCountMin: 3,
            wordCountMax: 3,
            pool: ["cat", "dog", "star"],
            seed: 1
        )
        guard let slot = engine.slots.first(where: { $0.word == "cat" }),
              let token = engine.tray.first(where: { $0.letter == "c" }),
              let other = engine.tray.first(where: { $0.letter == "d" }) else {
            Issue.record("expected tokens")
            return
        }
        _ = engine.plug(letterID: token.id, intoSlotID: slot.id)
        let events = engine.plug(letterID: other.id, intoSlotID: slot.id)
        #expect(events.isEmpty)
    }

    @Test func sampleWordCountClampsToPoolAndNine() {
        var rng = SeededGenerator(seed: 1)
        #expect(
            GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 3,
                maximum: 6,
                poolSize: 3,
                rng: &rng
            ) == 3
        )
        #expect(
            GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 3,
                maximum: 6,
                poolSize: 1,
                rng: &rng
            ) == 1
        )
        for _ in 0..<20 {
            let count = GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 3,
                maximum: 12,
                poolSize: 20,
                rng: &rng
            )
            #expect(count <= 9)
            #expect(count.isMultiple(of: 3))
        }
    }

    @Test func sampleWordCountKeepsPickWhenNoMultipleOfThreeInRange() {
        var rng = SeededGenerator(seed: 1)
        for _ in 0..<20 {
            let count = GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 2,
                maximum: 2,
                poolSize: 10,
                rng: &rng
            )
            #expect(count == 2)
        }
        for _ in 0..<20 {
            let count = GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 4,
                maximum: 5,
                poolSize: 10,
                rng: &rng
            )
            #expect((4...5).contains(count))
        }
    }

    @Test func sampleWordCountSnapsToNearestMultipleOfThreeInRange() {
        var rng = SeededGenerator(seed: 7)
        // Only 3 is a multiple of 3 in [2, 5].
        for _ in 0..<40 {
            let count = GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 2,
                maximum: 5,
                poolSize: 10,
                rng: &rng
            )
            #expect(count == 3)
        }
        // Only 6 is a multiple of 3 in [4, 6].
        for _ in 0..<40 {
            let count = GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 4,
                maximum: 6,
                poolSize: 10,
                rng: &rng
            )
            #expect(count == 6)
        }
        // [2, 8] can snap to 3 or 6.
        var seen: Set<Int> = []
        for _ in 0..<80 {
            let count = GateWordPlugMinigameEngine.sampleWordCount(
                minimum: 2,
                maximum: 8,
                poolSize: 20,
                rng: &rng
            )
            #expect([3, 6].contains(count))
            seen.insert(count)
        }
        #expect(seen == [3, 6])
    }

    @Test func nearestMultipleOfThreePrefersCloserThenLower() {
        #expect(GateWordPlugMinigameEngine.nearestMultipleOfThree(to: 2, in: 2...5) == 3)
        #expect(GateWordPlugMinigameEngine.nearestMultipleOfThree(to: 5, in: 3...6) == 6)
        #expect(GateWordPlugMinigameEngine.nearestMultipleOfThree(to: 4, in: 3...6) == 3)
        #expect(GateWordPlugMinigameEngine.nearestMultipleOfThree(to: 2, in: 2...2) == nil)
        #expect(GateWordPlugMinigameEngine.nearestMultipleOfThree(to: 4, in: 4...5) == nil)
    }
}
