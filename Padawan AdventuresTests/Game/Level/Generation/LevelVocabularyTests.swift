import Foundation
import Testing
@testable import Padawan_Adventures

struct LevelVocabularyTests {
    private func word(_ id: String, graphemes: [String]? = nil) -> GateWord {
        WordCatalog.imagedFallbackEntry(word: id, graphemes: graphemes)
    }

    private func grapheme(_ id: String) -> GateGrapheme {
        GateGrapheme(grapheme: id, pronunciation: "p_\(id)", name: "n_\(id)")
    }

    private func catalog(
        _ specs: [Int: (graphemes: [String], words: [String])]
    ) -> LevelVocabularyCatalog {
        LevelVocabularyCatalog(
            specsByOrder: specs.mapValues {
                LevelVocabularySpec(graphemes: $0.graphemes, words: $0.words)
            }
        )
    }

    private func wordCatalog(ids: [String]) -> WordCatalog {
        WordCatalog(words: ids.map { word($0) })
    }

    private func graphemeCatalog(ids: [String]) -> GraphemeCatalog {
        GraphemeCatalog(graphemes: ids.map(grapheme))
    }

    // MARK: - Tier weights

    @Test func tierWeightsLevel1IsOne() throws {
        let cat = catalog([1: (["a", "t"], ["at"])])
        let pool = try cat.pool(
            forOrder: 1,
            probability: 0.75,
            wordCatalog: wordCatalog(ids: ["at"]),
            graphemeCatalog: graphemeCatalog(ids: ["a", "t"])
        )
        #expect(pool.tiers.map(\.weight) == [1.0])
    }

    @Test func tierWeightsLevel2SplitsCurrentAndPrior() throws {
        let cat = catalog([
            1: (["a", "t"], ["at"]),
            2: (["m", "d"], ["mad"]),
        ])
        let pool = try cat.pool(
            forOrder: 2,
            probability: 0.75,
            wordCatalog: wordCatalog(ids: ["at", "mad"]),
            graphemeCatalog: graphemeCatalog(ids: ["a", "t", "m", "d"])
        )
        #expect(pool.tiers.map(\.order) == [1, 2])
        #expect(pool.tiers[0].weight == 0.25)
        #expect(pool.tiers[1].weight == 0.75)
    }

    @Test func tierWeightsLevel3GeometricSeries() throws {
        let cat = catalog([
            1: (["a"], ["at"]),
            2: (["m"], ["mad"]),
            3: (["r"], ["run"]),
        ])
        let pool = try cat.pool(
            forOrder: 3,
            probability: 0.75,
            wordCatalog: wordCatalog(ids: ["at", "mad", "run"]),
            graphemeCatalog: graphemeCatalog(ids: ["a", "m", "r"])
        )
        #expect(pool.tiers.map(\.order) == [1, 2, 3])
        #expect(pool.tiers[0].weight == 0.0625)
        #expect(pool.tiers[1].weight == 0.1875)
        #expect(pool.tiers[2].weight == 0.75)
    }

    @Test func tierWeightsHigherOrdersSpotCheck() throws {
        let cat = LevelVocabularyCatalog(specsByOrder: [
            1: LevelVocabularySpec(graphemes: ["a", "b", "c", "d", "e"], words: ["wa"]),
            2: LevelVocabularySpec(words: ["wb"]),
            3: LevelVocabularySpec(words: ["wc"]),
            4: LevelVocabularySpec(words: ["wd"]),
            5: LevelVocabularySpec(words: ["we"]),
        ])
        let pool = try cat.pool(
            forOrder: 5,
            probability: 0.75,
            wordCatalog: wordCatalog(ids: ["wa", "wb", "wc", "wd", "we"]),
            graphemeCatalog: graphemeCatalog(ids: ["a", "b", "c", "d", "e"])
        )
        #expect(pool.tiers.count == 5)
        #expect(pool.tiers[4].weight == 0.75)
        #expect(pool.tiers[3].weight == 0.1875)
        #expect(pool.tiers[2].weight == 0.046875)
        let sum = pool.tiers.reduce(0.0) { $0 + $1.weight }
        #expect(abs(sum - 1.0) < 1e-12)
        #expect(pool.tiers[0].weight == 1.0 - pool.tiers.dropFirst().reduce(0.0) { $0 + $1.weight })
    }

    // MARK: - Cumulative membership

    @Test func cumulativePoolIncludesEarlierLevels() throws {
        let cat = catalog([
            1: (["s", "a", "t"], ["sat", "at"]),
            2: (["m", "d"], ["mad", "dog"]),
        ])
        let pool = try cat.pool(
            forOrder: 2,
            probability: 0.75,
            wordCatalog: wordCatalog(ids: ["sat", "at", "mad", "dog"]),
            graphemeCatalog: graphemeCatalog(ids: ["s", "a", "t", "m", "d"])
        )
        #expect(Set(pool.allWords.map(\.word)) == ["sat", "at", "mad", "dog"])
        #expect(Set(pool.allGraphemes.map(\.grapheme)) == ["s", "a", "t", "m", "d"])
    }

    // MARK: - Lowest-order binding

    @Test func lowestOrderWinsOnDuplicateIDs() {
        let cat = LevelVocabularyCatalog(specsByOrder: [
            1: LevelVocabularySpec(graphemes: ["a", "t"], words: ["at", "cat"]),
            2: LevelVocabularySpec(graphemes: ["a", "m"], words: ["cat", "mad"]),
        ])
        #expect(cat.specsByOrder[1]?.words == ["at", "cat"])
        #expect(cat.specsByOrder[2]?.words == ["mad"])
        #expect(cat.specsByOrder[1]?.graphemes == ["a", "t"])
        #expect(cat.specsByOrder[2]?.graphemes == ["m"])
        #expect(cat.duplicateWordIDs == ["cat"])
        #expect(cat.duplicateGraphemeIDs == ["a"])
    }

    // MARK: - Sampling without replacement

    @Test func pickWordsDoesNotRepeatWithinACall() {
        let words = ["at", "sat", "sit", "pat", "nap", "pan"].map { word($0) }
        let pool = LevelVocabularyPool(tiers: [
            .init(order: 1, weight: 1, words: words, graphemes: []),
        ])
        var rng = SeededGenerator(seed: 11)
        let picked = pool.pickWords(count: 4, using: &rng)
        #expect(picked.count == 4)
        #expect(Set(picked.map(\.word)).count == 4)
    }

    @Test func pickGraphemesDoesNotRepeatWithinACall() {
        let graphemes = ["s", "a", "t", "p", "i", "n"].map(grapheme)
        let pool = LevelVocabularyPool(tiers: [
            .init(order: 1, weight: 1, words: [], graphemes: graphemes),
        ])
        var rng = SeededGenerator(seed: 3)
        let picked = pool.pickGraphemes(count: 5, using: &rng)
        #expect(picked.count == 5)
        #expect(Set(picked.map(\.grapheme)).count == 5)
    }

    // MARK: - Grapheme-span masking

    @Test func startingMaskBlanksFullGraphemeSpan() {
        let stop = word("stop", graphemes: ["st", "o", "p"])
        #expect(GateWordPlugLetterPosition.starting.answerGrapheme(in: stop) == "st")
        #expect(GateWordPlugLetterPosition.starting.maskedText(for: stop) == "__op")
    }

    @Test func endingMaskBlanksFullGraphemeSpan() {
        let high = word("high", graphemes: ["h", "igh"])
        #expect(GateWordPlugLetterPosition.ending.answerGrapheme(in: high) == "igh")
        #expect(GateWordPlugLetterPosition.ending.maskedText(for: high) == "h___")
    }

    @Test func matchesUsesGraphemeBreakdownNotStringSuffix() {
        let fast = word("fast", graphemes: ["f", "a", "st"])
        #expect(GateWordPlugLetterPosition.ending.matches(grapheme: "st", in: fast))
        #expect(!GateWordPlugLetterPosition.ending.matches(grapheme: "t", in: fast))
        #expect(GateWordPlugLetterPosition.starting.matches(grapheme: "f", in: fast))
        #expect(!GateWordPlugLetterPosition.starting.matches(grapheme: "fa", in: fast))
    }
}
