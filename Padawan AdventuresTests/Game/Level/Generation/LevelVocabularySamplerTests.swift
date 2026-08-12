import Foundation
import Testing
@testable import Padawan_Adventures

struct LevelVocabularySamplerTests {
    private func word(_ id: String) -> GateWord {
        WordCatalog.imagedFallbackEntry(word: id)
    }

    private func grapheme(_ id: String) -> GateGrapheme {
        GateGrapheme(grapheme: id, pronunciation: "p_\(id)", name: "n_\(id)")
    }

    private func twoTierWordPool() -> (pool: LevelVocabularyPool, prior: Set<String>, current: Set<String>) {
        let prior = ["sat", "sit", "sip", "sap"]
        let current = ["sun", "sum", "sob", "sod"]
        let pool = LevelVocabularyPool(tiers: [
            .init(order: 1, weight: 0.25, words: prior.map(word), graphemes: []),
            .init(order: 2, weight: 0.75, words: current.map(word), graphemes: []),
        ])
        return (pool, Set(prior), Set(current))
    }

    private func twoTierGraphemePool() -> (pool: LevelVocabularyPool, prior: Set<String>, current: Set<String>) {
        let prior = ["s", "a", "t", "p"]
        let current = ["m", "d", "g", "o"]
        let pool = LevelVocabularyPool(tiers: [
            .init(order: 1, weight: 0.25, words: [], graphemes: prior.map(grapheme)),
            .init(order: 2, weight: 0.75, words: [], graphemes: current.map(grapheme)),
        ])
        return (pool, Set(prior), Set(current))
    }

    @Test func takeWordsDoesNotRepeat() {
        let words = ["at", "sat", "sit", "pat", "nap", "pan"].map(word)
        var sampler = LevelVocabularySampler(pool: .singleTier(words: words))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 11)
        let picked = sampler.takeWords(count: 4, using: &rng)
        #expect(picked.count == 4)
        #expect(Set(picked.map(\.word)).count == 4)
    }

    @Test func takeGraphemesDoesNotRepeat() {
        let graphemes = ["s", "a", "t", "p", "i", "n"].map(grapheme)
        var sampler = LevelVocabularySampler(pool: .singleTier(graphemes: graphemes))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 3)
        let picked = sampler.takeGraphemes(count: 5, using: &rng)
        #expect(picked.count == 5)
        #expect(Set(picked.map(\.grapheme)).count == 5)
    }

    @Test func takeWordsStopsWhenPoolIsExhausted() {
        let words = ["at", "sat"].map(word)
        var sampler = LevelVocabularySampler(pool: .singleTier(words: words))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 1)
        let picked = sampler.takeWords(count: 5, using: &rng)
        #expect(Set(picked.map(\.word)) == ["at", "sat"])
    }

    @Test func nextWordRefillsAfterExhaustion() {
        let words = ["at", "sat"].map(word)
        var sampler = LevelVocabularySampler(pool: .singleTier(words: words))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 2)
        var seen: [String] = []
        for _ in 0..<4 {
            guard let entry = sampler.nextWord(using: &rng) else {
                Issue.record("expected a refill draw")
                return
            }
            seen.append(entry.word)
        }
        #expect(Set(seen.prefix(2)) == ["at", "sat"])
        #expect(Set(seen.suffix(2)).isSubset(of: ["at", "sat"]))
    }

    @Test func nextGraphemeSkipsExcludedIdsUntilRefill() {
        let graphemes = ["s", "a", "t"].map(grapheme)
        var sampler = LevelVocabularySampler(pool: .singleTier(graphemes: graphemes))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 4)
        var seen: [String] = []
        var last = ""
        for _ in 0..<6 {
            let excluding = last.isEmpty ? Set<String>() : [last]
            guard let entry = sampler.nextGrapheme(excluding: excluding, using: &rng) else {
                Issue.record("expected a grapheme")
                return
            }
            #expect(entry.grapheme != last)
            seen.append(entry.grapheme)
            last = entry.grapheme
        }
        #expect(Set(seen.prefix(3)) == ["s", "a", "t"])
    }

    @Test func graphemeIdentityIgnoresCase() {
        let graphemes = ["s", "S", "a", "A"].map(grapheme)
        var sampler = LevelVocabularySampler(pool: .singleTier(graphemes: graphemes))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 1)
        let picked = sampler.takeGraphemes(count: 5, using: &rng)
        #expect(picked.count == 2)
        #expect(Set(picked.map { $0.grapheme.lowercased() }) == ["s", "a"])
    }

    @Test func nextGraphemeExcludingIgnoresCase() {
        let graphemes = ["s", "a"].map(grapheme)
        var sampler = LevelVocabularySampler(pool: .singleTier(graphemes: graphemes))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 2)
        let first = sampler.nextGrapheme(excluding: ["S"], using: &rng)
        #expect(first?.grapheme == "a")
    }

    @Test func nextWordPrefersCurrentLevelTier() {
        let spec = twoTierWordPool()
        var currentHits = 0
        let trials = 200
        for seed in UInt64(1)...UInt64(trials) {
            var sampler = LevelVocabularySampler(pool: spec.pool)
            var rng: any RandomNumberGenerator = SeededGenerator(seed: seed)
            guard let picked = sampler.nextWord(using: &rng) else {
                Issue.record("expected a word")
                return
            }
            if spec.current.contains(picked.word) { currentHits += 1 }
        }
        #expect(currentHits > trials / 2)
    }

    @Test func nextGraphemePrefersCurrentLevelTier() {
        let spec = twoTierGraphemePool()
        var currentHits = 0
        let trials = 200
        for seed in UInt64(1)...UInt64(trials) {
            var sampler = LevelVocabularySampler(pool: spec.pool)
            var rng: any RandomNumberGenerator = SeededGenerator(seed: seed)
            guard let picked = sampler.nextGrapheme(using: &rng) else {
                Issue.record("expected a grapheme")
                return
            }
            if spec.current.contains(picked.grapheme) { currentHits += 1 }
        }
        #expect(currentHits > trials / 2)
    }

    @Test func takeGraphemesCanDrawFromPriorAndCurrentTiers() {
        let spec = twoTierGraphemePool()
        var seen: Set<String> = []
        for seed in UInt64(1)...80 {
            var sampler = LevelVocabularySampler(pool: spec.pool)
            var rng: any RandomNumberGenerator = SeededGenerator(seed: seed)
            seen.formUnion(sampler.takeGraphemes(count: 3, using: &rng).map(\.grapheme))
        }
        #expect(!seen.isDisjoint(with: spec.prior))
        #expect(!seen.isDisjoint(with: spec.current))
    }

    @Test func resetRestoresTheFullPool() {
        let words = ["at", "sat", "sit"].map(word)
        var sampler = LevelVocabularySampler(pool: .singleTier(words: words))
        var rng: any RandomNumberGenerator = SeededGenerator(seed: 8)
        _ = sampler.takeWords(count: 3, using: &rng)
        #expect(sampler.takeWords(count: 1, using: &rng).isEmpty)
        sampler.reset()
        #expect(sampler.takeWords(count: 3, using: &rng).count == 3)
    }
}
