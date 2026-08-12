import Foundation
import Yams

/// One level's declared vocabulary ids from the top-level `vocab:` block.
nonisolated struct LevelVocabularySpec: Decodable, Equatable, Sendable {
    var graphemes: [String]
    var words: [String]

    nonisolated init(graphemes: [String] = [], words: [String] = []) {
        self.graphemes = graphemes.map { $0.lowercased() }
        self.words = words.map { $0.lowercased() }
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        graphemes = (try container.decodeIfPresent([String].self, forKey: .graphemes) ?? [])
            .map { $0.lowercased() }
        words = (try container.decodeIfPresent([String].self, forKey: .words) ?? [])
            .map { $0.lowercased() }
    }

    private enum CodingKeys: String, CodingKey {
        case graphemes
        case words
    }
}

/// Cross-level map of curriculum order → declared `vocab:` (lowest order wins on id clashes).
nonisolated struct LevelVocabularyCatalog: Equatable, Sendable {
    /// Specs keyed by level `order`, after dropping higher-order duplicate ids.
    private(set) var specsByOrder: [Int: LevelVocabularySpec]
    /// Word ids declared in more than one level's `vocab:` block.
    private(set) var duplicateWordIDs: [String]
    /// Grapheme ids declared in more than one level's `vocab:` block.
    private(set) var duplicateGraphemeIDs: [String]

    nonisolated init(specsByOrder: [Int: LevelVocabularySpec]) {
        let bound = Self.bindLowestOrder(specsByOrder)
        self.specsByOrder = bound.specs
        self.duplicateWordIDs = bound.duplicateWords
        self.duplicateGraphemeIDs = bound.duplicateGraphemes
    }

    /// Offline / missing-resource stand-in: the full fallback word + grapheme catalogs as order 1.
    nonisolated static let fallback = LevelVocabularyCatalog(specsByOrder: [
        1: LevelVocabularySpec(
            graphemes: GraphemeCatalog.fallback.graphemes.map(\.grapheme),
            words: WordCatalog.fallback.words.map(\.word)
        ),
    ])

    static func loadFromBundle() throws -> LevelVocabularyCatalog {
        var collected: [(order: Int, spec: LevelVocabularySpec)] = []
        for levelID in LevelCatalog.levelIDs() {
            let path = ConfigPath.levelBase(levelID)
            let data = try ConfigStore.data(at: path)
            let tree = try ConfigStore.rawTree(
                from: data,
                parentDataNamed: { parentName in
                    try ConfigStore.data(at: ConfigPath.levelBase(parentName))
                },
                fileLabel: path.description
            )
            let order = (tree["order"] as? Int)
                ?? (tree["order"] as? NSNumber)?.intValue
                ?? 0
            guard let vocabValue = tree["vocab"],
                  let vocabDict = ConfigStore.asStringKeyedDictionary(vocabValue) else {
                continue
            }
            let yaml = try Yams.dump(object: vocabDict)
            let spec = try YAMLDecoder().decode(LevelVocabularySpec.self, from: yaml)
            guard !spec.words.isEmpty || !spec.graphemes.isEmpty else { continue }
            collected.append((order, spec))
        }

        var byOrder: [Int: LevelVocabularySpec] = [:]
        for entry in collected {
            // Later files with the same order replace earlier ones (should not happen in practice).
            byOrder[entry.order] = entry.spec
        }
        return LevelVocabularyCatalog(specsByOrder: byOrder)
    }

    /// Builds the cumulative tiered pool for `1...max(order, 1)` so `_defaults` (order 0) gets Level 1.
    func pool(
        forOrder order: Int,
        probability: Double,
        wordCatalog: WordCatalog,
        graphemeCatalog: GraphemeCatalog
    ) throws -> LevelVocabularyPool {
        let target = max(order, 1)
        var tiers: [LevelVocabularyPool.Tier] = []
        for tierOrder in 1...target {
            guard let spec = specsByOrder[tierOrder] else { continue }
            var words: [GateWord] = []
            words.reserveCapacity(spec.words.count)
            for id in spec.words {
                guard let entry = wordCatalog.word(named: id) else {
                    throw WorldSeedError.invalidGateWords
                }
                words.append(entry)
            }
            var graphemes: [GateGrapheme] = []
            graphemes.reserveCapacity(spec.graphemes.count)
            for id in spec.graphemes {
                guard let entry = graphemeCatalog.grapheme(named: id) else {
                    throw WorldSeedError.invalidGateGraphemeMatchGraphemes
                }
                graphemes.append(entry)
            }
            words = GateWord.normalized(words)
            // Preserve declaration order for graphemes (deflect rings / stable flatten).
            let orderedGraphemes = graphemes.map {
                GateGrapheme(
                    grapheme: $0.grapheme.lowercased(),
                    pronunciation: $0.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            guard !words.isEmpty || !orderedGraphemes.isEmpty else { continue }
            tiers.append(
                LevelVocabularyPool.Tier(
                    order: tierOrder,
                    weight: 0,
                    words: words,
                    graphemes: orderedGraphemes
                )
            )
        }
        return LevelVocabularyPool(tiers: tiers, probability: probability)
    }

    /// Keeps each id on the lowest declaring order; records clashes for audit.
    private static func bindLowestOrder(
        _ specsByOrder: [Int: LevelVocabularySpec]
    ) -> (specs: [Int: LevelVocabularySpec], duplicateWords: [String], duplicateGraphemes: [String]) {
        var wordOwner: [String: Int] = [:]
        var graphemeOwner: [String: Int] = [:]
        var duplicateWords = Set<String>()
        var duplicateGraphemes = Set<String>()
        var result: [Int: LevelVocabularySpec] = [:]

        for order in specsByOrder.keys.sorted() {
            guard let spec = specsByOrder[order] else { continue }
            var words: [String] = []
            var graphemes: [String] = []
            for raw in spec.words {
                let id = raw.lowercased()
                if let existing = wordOwner[id] {
                    if existing != order { duplicateWords.insert(id) }
                    continue
                }
                wordOwner[id] = order
                words.append(id)
            }
            for raw in spec.graphemes {
                let id = raw.lowercased()
                if let existing = graphemeOwner[id] {
                    if existing != order { duplicateGraphemes.insert(id) }
                    continue
                }
                graphemeOwner[id] = order
                graphemes.append(id)
            }
            if !words.isEmpty || !graphemes.isEmpty {
                result[order] = LevelVocabularySpec(graphemes: graphemes, words: words)
            }
        }
        return (
            result,
            duplicateWords.sorted(),
            duplicateGraphemes.sorted()
        )
    }
}

/// Resolved cumulative vocabulary pool with geometric tier weights.
/// Draws go through `LevelVocabularySampler` so every minigame shares the same
/// without-replacement, current-level-weighted behaviour for words and graphemes.
nonisolated struct LevelVocabularyPool: Equatable, Sendable {
    nonisolated struct Tier: Equatable, Sendable {
        var order: Int
        var weight: Double
        var words: [GateWord]
        var graphemes: [GateGrapheme]
    }

    var tiers: [Tier]

    /// Flattened words across tiers, deduped, first-seen order preserved.
    var allWords: [GateWord] {
        var seen = Set<String>()
        var out: [GateWord] = []
        for tier in tiers {
            for word in tier.words where seen.insert(word.word).inserted {
                out.append(word)
            }
        }
        return out
    }

    /// Flattened graphemes across tiers, deduped, first-seen order preserved.
    var allGraphemes: [GateGrapheme] {
        var seen = Set<String>()
        var out: [GateGrapheme] = []
        for tier in tiers {
            for grapheme in tier.graphemes where seen.insert(grapheme.grapheme.lowercased()).inserted {
                out.append(grapheme)
            }
        }
        return out
    }

    /// Single-character grapheme ids only (stable order from `allGraphemes`).
    var letters: [String] {
        allGraphemes.compactMap { entry in
            entry.grapheme.count == 1 ? entry.grapheme : nil
        }
    }

    /// Offline stand-in used by `LevelConfig.fallback`.
    nonisolated static let fallback = LevelVocabularyPool(
        tiers: [
            Tier(
                order: 1,
                weight: 1,
                words: WordCatalog.fallback.words,
                graphemes: GraphemeCatalog.fallback.graphemes
            ),
        ]
    )

    nonisolated static let empty = LevelVocabularyPool(tiers: [])

    /// Single-tier pool for tests / configs that only have flat word/grapheme arrays.
    nonisolated static func singleTier(
        words: [GateWord] = [],
        graphemes: [GateGrapheme] = [],
        order: Int = 1
    ) -> LevelVocabularyPool {
        guard !words.isEmpty || !graphemes.isEmpty else { return .empty }
        return LevelVocabularyPool(
            tiers: [
                Tier(order: order, weight: 1, words: words, graphemes: graphemes),
            ]
        )
    }

    nonisolated init(tiers: [Tier]) {
        self.tiers = tiers
    }

    /// Assigns geometric weights from `probability` (current-level mass).
    nonisolated init(tiers: [Tier], probability: Double) {
        let p = min(max(probability, 0), 1)
        var built = tiers
        let count = built.count
        if count == 0 {
            self.tiers = []
            return
        }
        if count == 1 {
            built[0].weight = 1
            self.tiers = built
            return
        }
        built[count - 1].weight = p
        var assigned = p
        if count > 2 {
            for index in stride(from: count - 2, through: 1, by: -1) {
                let k = (count - 1) - index
                let weight = pow(1 - p, Double(k)) * p
                built[index].weight = weight
                assigned += weight
            }
        }
        built[0].weight = max(0, 1 - assigned)
        self.tiers = built
    }

    func pickWord(using rng: inout any RandomNumberGenerator) -> GateWord? {
        var sampler = LevelVocabularySampler(pool: self)
        return sampler.nextWord(refillWhenEmpty: false, using: &rng)
    }

    func pickWords(count: Int, using rng: inout any RandomNumberGenerator) -> [GateWord] {
        var sampler = LevelVocabularySampler(pool: self)
        return sampler.takeWords(count: count, using: &rng)
    }

    func pickGrapheme(using rng: inout any RandomNumberGenerator) -> GateGrapheme? {
        var sampler = LevelVocabularySampler(pool: self)
        return sampler.nextGrapheme(refillWhenEmpty: false, using: &rng)
    }

    func pickGraphemes(count: Int, using rng: inout any RandomNumberGenerator) -> [GateGrapheme] {
        var sampler = LevelVocabularySampler(pool: self)
        return sampler.takeGraphemes(count: count, using: &rng)
    }

    func filteringWords(_ isIncluded: (GateWord) -> Bool) -> LevelVocabularyPool {
        let filtered = tiers.compactMap { tier -> Tier? in
            let words = tier.words.filter(isIncluded)
            guard !words.isEmpty || !tier.graphemes.isEmpty else { return nil }
            guard !words.isEmpty else {
                // Drop tiers that lose all words when the filter is word-focused.
                return nil
            }
            return Tier(order: tier.order, weight: tier.weight, words: words, graphemes: tier.graphemes)
        }
        return Self.renormalized(filtered)
    }

    func filteringGraphemes(_ isIncluded: (GateGrapheme) -> Bool) -> LevelVocabularyPool {
        let filtered = tiers.compactMap { tier -> Tier? in
            let graphemes = tier.graphemes.filter(isIncluded)
            guard !graphemes.isEmpty else { return nil }
            return Tier(order: tier.order, weight: tier.weight, words: tier.words, graphemes: graphemes)
        }
        return Self.renormalized(filtered)
    }

    private static func renormalized(_ tiers: [Tier]) -> LevelVocabularyPool {
        let total = tiers.reduce(0.0) { $0 + max($1.weight, 0) }
        guard total > 0 else {
            return LevelVocabularyPool(tiers: tiers.map {
                Tier(order: $0.order, weight: tiers.count == 1 ? 1 : 0, words: $0.words, graphemes: $0.graphemes)
            })
        }
        return LevelVocabularyPool(tiers: tiers.map {
            Tier(
                order: $0.order,
                weight: max($0.weight, 0) / total,
                words: $0.words,
                graphemes: $0.graphemes
            )
        })
    }
}
