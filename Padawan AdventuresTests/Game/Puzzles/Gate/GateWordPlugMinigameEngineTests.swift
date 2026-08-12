import Foundation
import Testing
@testable import Padawan_Adventures

struct GateWordPlugMinigameEngineTests {
    private func letters(_ values: [String]) -> [GateGrapheme] {
        values.map {
            GateGrapheme(
                grapheme: $0,
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
        letterPosition: GateWordPlugLetterPosition = .starting,
        pool: [String] = ["cat", "dog", "sat", "map", "can"],
        letterPool: [String] = ["a", "b", "c", "d", "e", "f", "g", "h", "o", "s"],
        seed: UInt64 = 42
    ) -> GateWordPlugMinigameEngine {
        var engine = GateWordPlugMinigameEngine(
            config: .init(
                wordCountMin: wordCountMin,
                wordCountMax: wordCountMax,
                letterPosition: letterPosition,
                words: words(pool),
                graphemes: letters(letterPool)
            ),
            rng: SeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    @Test func constructsInactive() {
        let engine = GateWordPlugMinigameEngine(
            config: .init(words: words(["cat"]), graphemes: letters(["c"]))
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
                pool: ["cat", "dog", "sat", "map", "can"],
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
                pool: ["cat", "dog", "sat", "map", "can"],
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
        let pool = ["bed", "bug", "cat", "dad", "dog", "pig", "sat", "web"]
        var seen: Set<String> = []
        for seed in UInt64(1)...60 {
            let engine = makeEngine(
                wordCountMin: 2,
                wordCountMax: 2,
                pool: pool,
                letterPool: ["b", "c", "d", "p", "s", "w"],
                seed: seed
            )
            #expect(engine.slots.count == 2)
            seen.formUnion(engine.slots.map(\.word))
        }
        #expect(seen == Set(pool))
    }

    @Test func roundDropsAWordRatherThanRepeatingAPlugLetter() {
        let engine = makeEngine(
            wordCountMin: 2,
            wordCountMax: 2,
            pool: ["bed", "bug"],
            letterPool: ["b"],
            seed: 7
        )
        #expect(engine.slots.count == 1)
        #expect(engine.tray.map(\.letter) == ["b"])
    }

    @Test func trayLettersStayUniqueAcrossSeedsAndPositions() {
        for position in [GateWordPlugLetterPosition.starting, .ending] {
            for seed in UInt64(1)...60 {
                let engine = makeEngine(
                    wordCountMin: 1,
                    wordCountMax: 9,
                    letterPosition: position,
                    pool: ["bed", "bug", "cat", "dad", "dog", "pig", "sat", "web", "can"],
                    letterPool: ["a", "b", "c", "d", "g", "n", "p", "s", "t", "w"],
                    seed: seed
                )
                #expect(Set(engine.tray.map(\.letter)).count == engine.tray.count)
                #expect(Set(engine.slots.map(\.letter)).count == engine.slots.count)
            }
        }
    }

    @Test func maskedTextReplacesFirstLetter() {
        let engine = makeEngine(seed: 7)
        for slot in engine.slots {
            #expect(slot.maskedText == "_\(slot.word.dropFirst())")
            #expect(slot.maskedText.first == "_")
        }
    }

    @Test func endingModeMasksLastLetter() {
        let engine = makeEngine(
            letterPosition: .ending,
            pool: ["dog", "web", "coat"],
            letterPool: ["b", "d", "g", "t"],
            seed: 7
        )
        for slot in engine.slots {
            #expect(slot.maskedText == "\(slot.word.dropLast())_")
            #expect(slot.maskedText.last == "_")
            #expect(slot.letter == String(slot.word.suffix(1)))
        }
    }

    @Test func digraphStartingMaskBlanksFullGraphemeSpan() {
        var engine = GateWordPlugMinigameEngine(
            config: .init(
                wordCountMin: 1,
                wordCountMax: 1,
                letterPosition: .starting,
                words: [WordCatalog.imagedFallbackEntry(word: "stop", graphemes: ["st", "o", "p"])],
                graphemes: letters(["st", "o", "p"])
            ),
            rng: SeededGenerator(seed: 1)
        )
        engine.begin()
        #expect(engine.slots.count == 1)
        #expect(engine.slots[0].maskedText == "__op")
        #expect(engine.slots[0].letter == "st")
    }

    @Test func digraphEndingMaskBlanksFullGraphemeSpan() {
        var engine = GateWordPlugMinigameEngine(
            config: .init(
                wordCountMin: 1,
                wordCountMax: 1,
                letterPosition: .ending,
                words: [WordCatalog.imagedFallbackEntry(word: "high", graphemes: ["h", "igh"])],
                graphemes: letters(["h", "igh"])
            ),
            rng: SeededGenerator(seed: 1)
        )
        engine.begin()
        #expect(engine.slots.count == 1)
        #expect(engine.slots[0].maskedText == "h___")
        #expect(engine.slots[0].letter == "igh")
    }

    @Test func endingModePluggingEverySlotWinsAndAwardsStars() {
        var engine = makeEngine(
            wordCountMin: 3,
            wordCountMax: 3,
            letterPosition: .ending,
            pool: ["dog", "web", "coat"],
            letterPool: ["b", "d", "g", "t"],
            seed: 5
        )
        #expect(engine.slots.count == 3)
        for slot in engine.slots {
            guard let token = engine.tray.first(where: {
                $0.letter == slot.letter && !engine.isTokenPlugged($0.id)
            }) else {
                Issue.record("missing token for \(slot.letter)")
                return
            }
            _ = engine.plug(letterID: token.id, intoSlotID: slot.id)
        }
        #expect(engine.outcome == .won(starsAwarded: engine.slots.count))
        #expect(engine.isFrozen)
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
            .playGraphemeSound(trackID: token.pronunciationTrackID),
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
            pool: ["cat", "dog", "sat"],
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
            pool: ["cat", "dog", "sat"],
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
            (3, 3, ["cat", "dog", "sat"]),
            (6, 6, ["cat", "dog", "sat", "map", "bed", "fun"]),
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
            pool: ["cat", "dog", "sat"],
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
            pool: ["cat", "dog", "sat"],
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

    @Test func beginSamplesWithoutReplacementFromCumulativePool() {
        let prior = ["sat", "pat", "tap"].map { WordCatalog.imagedFallbackEntry(word: $0) }
        let current = ["dog", "mad", "cat"].map { WordCatalog.imagedFallbackEntry(word: $0) }
        let pool = LevelVocabularyPool(tiers: [
            .init(
                order: 1,
                weight: 0.25,
                words: prior,
                graphemes: letters(["s", "p", "t"])
            ),
            .init(
                order: 2,
                weight: 0.75,
                words: current,
                graphemes: letters(["d", "m", "c"])
            ),
        ])
        let currentIDs = Set(current.map(\.word))
        var currentHits = 0
        var seen: Set<String> = []
        let trials = 80
        for seed in UInt64(1)...UInt64(trials) {
            var engine = GateWordPlugMinigameEngine(
                config: .init(
                    wordCountMin: 2,
                    wordCountMax: 2,
                    words: prior + current,
                    graphemes: letters(["s", "p", "t", "d", "m", "c"]),
                    vocabulary: pool
                ),
                rng: SeededGenerator(seed: seed)
            )
            engine.begin()
            #expect(Set(engine.slots.map(\.word)).count == engine.slots.count)
            seen.formUnion(engine.slots.map(\.word))
            if engine.slots.contains(where: { currentIDs.contains($0.word) }) {
                currentHits += 1
            }
        }
        #expect(!seen.isDisjoint(with: Set(prior.map(\.word))))
        #expect(!seen.isDisjoint(with: currentIDs))
        #expect(currentHits > trials / 2)
    }
}
