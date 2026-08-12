import Foundation

/// Weighted without-replacement draws from a cumulative `LevelVocabularyPool`.
///
/// Each draw picks a tier with that tier's weight (`current_level_probability` for the
/// current level, earlier levels splitting the rest geometrically), then a uniform
/// entry from what remains in the tier. Drawn ids are removed until the eligible
/// remainder is empty; `refillWhenEmpty` then restores the full pool so a long
/// session can continue.
///
/// One instance is owned by the level run (`AppSession.vocabularySampler`) and shared
/// across minigames so unused current-level words and graphemes keep being drawn
/// until the pool wraps.
final class LevelVocabularySampler {
    private(set) var pool: LevelVocabularyPool
    private var remainingWords: [[GateWord]]
    private var remainingGraphemes: [[GateGrapheme]]

    init(pool: LevelVocabularyPool) {
        self.pool = pool
        remainingWords = pool.tiers.map(\.words)
        remainingGraphemes = Self.identityGraphemes(pool.tiers.map(\.graphemes))
    }

    func reset() {
        remainingWords = pool.tiers.map(\.words)
        remainingGraphemes = Self.identityGraphemes(pool.tiers.map(\.graphemes))
    }

    func nextWord(
        excluding excluded: Set<String> = [],
        refillWhenEmpty: Bool = true,
        using rng: inout any RandomNumberGenerator
    ) -> GateWord? {
        nextWord(
            where: { !excluded.contains($0.word) },
            refillWhenEmpty: refillWhenEmpty,
            using: &rng
        )
    }

    func nextWord(
        where isIncluded: (GateWord) -> Bool,
        refillWhenEmpty: Bool = true,
        using rng: inout any RandomNumberGenerator
    ) -> GateWord? {
        pick(
            remaining: &remainingWords,
            refill: { pool.tiers.map(\.words) },
            isIncluded: isIncluded,
            refillWhenEmpty: refillWhenEmpty,
            using: &rng
        )
    }

    func nextGrapheme(
        excluding excluded: Set<String> = [],
        refillWhenEmpty: Bool = true,
        using rng: inout any RandomNumberGenerator
    ) -> GateGrapheme? {
        let ids = Set(excluded.map { $0.lowercased() })
        return nextGrapheme(
            where: { !ids.contains($0.grapheme.lowercased()) },
            refillWhenEmpty: refillWhenEmpty,
            using: &rng
        )
    }

    func nextGrapheme(
        where isIncluded: (GateGrapheme) -> Bool,
        refillWhenEmpty: Bool = true,
        using rng: inout any RandomNumberGenerator
    ) -> GateGrapheme? {
        pick(
            remaining: &remainingGraphemes,
            refill: { Self.identityGraphemes(pool.tiers.map(\.graphemes)) },
            isIncluded: isIncluded,
            refillWhenEmpty: refillWhenEmpty,
            using: &rng
        )
    }

    /// Batch draw. Does not repeat ids within the batch; if the unused set runs out
    /// mid-batch, refills the full pool and continues (same wrap as sequential draws).
    func takeWords(
        count: Int,
        excluding excluded: Set<String> = [],
        using rng: inout any RandomNumberGenerator
    ) -> [GateWord] {
        guard count > 0 else { return [] }
        var out: [GateWord] = []
        var seen = excluded
        var didRefill = false
        out.reserveCapacity(count)
        while out.count < count {
            if let item = nextWord(excluding: seen, refillWhenEmpty: false, using: &rng) {
                seen.insert(item.word)
                out.append(item)
                continue
            }
            guard !didRefill,
                  let item = nextWord(excluding: seen, refillWhenEmpty: true, using: &rng) else {
                break
            }
            didRefill = true
            seen.insert(item.word)
            out.append(item)
        }
        return out
    }

    /// Batch draw. Does not repeat ids within the batch; if the unused set runs out
    /// mid-batch, refills the full pool and continues (same wrap as sequential draws).
    func takeGraphemes(
        count: Int,
        excluding excluded: Set<String> = [],
        where isIncluded: ((GateGrapheme) -> Bool)? = nil,
        using rng: inout any RandomNumberGenerator
    ) -> [GateGrapheme] {
        guard count > 0 else { return [] }
        let ids = Set(excluded.map { $0.lowercased() })
        var out: [GateGrapheme] = []
        var seen = ids
        var didRefill = false
        out.reserveCapacity(count)
        while out.count < count {
            let matches: (GateGrapheme) -> Bool = { entry in
                let id = entry.grapheme.lowercased()
                guard !seen.contains(id) else { return false }
                return isIncluded?(entry) ?? true
            }
            if let item = nextGrapheme(where: matches, refillWhenEmpty: false, using: &rng) {
                seen.insert(item.grapheme.lowercased())
                out.append(item)
                continue
            }
            guard !didRefill,
                  let item = nextGrapheme(where: matches, refillWhenEmpty: true, using: &rng) else {
                break
            }
            didRefill = true
            seen.insert(item.grapheme.lowercased())
            out.append(item)
        }
        return out
    }

    private func pick<T>(
        remaining: inout [[T]],
        refill: () -> [[T]],
        isIncluded: (T) -> Bool,
        refillWhenEmpty: Bool,
        using rng: inout any RandomNumberGenerator
    ) -> T? {
        if let item = draw(from: &remaining, isIncluded: isIncluded, using: &rng) {
            return item
        }
        guard refillWhenEmpty else { return nil }
        var restored = refill()
        guard let item = draw(from: &restored, isIncluded: isIncluded, using: &rng) else {
            return nil
        }
        remaining = restored
        return item
    }

    private func draw<T>(
        from remaining: inout [[T]],
        isIncluded: (T) -> Bool,
        using rng: inout any RandomNumberGenerator
    ) -> T? {
        let weights = pool.tiers.map(\.weight)
        let live = remaining.indices.filter { index in
            remaining[index].contains(where: isIncluded)
        }
        guard !live.isEmpty else { return nil }

        let total = live.reduce(0.0) { sum, index in
            sum + max(index < weights.count ? weights[index] : 0, 0)
        }
        let chosen: Int
        if total > 0 {
            var roll = Double.random(in: 0..<total, using: &rng)
            var pick = live[live.count - 1]
            for index in live {
                roll -= max(index < weights.count ? weights[index] : 0, 0)
                if roll < 0 {
                    pick = index
                    break
                }
            }
            chosen = pick
        } else {
            chosen = live.randomElement(using: &rng)!
        }

        let eligible = remaining[chosen].indices.filter { isIncluded(remaining[chosen][$0]) }
        guard let offset = eligible.randomElement(using: &rng) else { return nil }
        return remaining[chosen].remove(at: offset)
    }

    /// Lowercased unique ids per tier. Case is not part of grapheme identity.
    private static func identityGraphemes(_ tiers: [[GateGrapheme]]) -> [[GateGrapheme]] {
        tiers.map { tier in
            var seen = Set<String>()
            return tier.compactMap { entry in
                let id = entry.grapheme.lowercased()
                guard !id.isEmpty, seen.insert(id).inserted else { return nil }
                return GateGrapheme(
                    grapheme: id,
                    pronunciation: entry.pronunciation,
                    name: entry.name
                )
            }
        }
    }
}
