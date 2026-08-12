import Foundation

/// How grapheme-sound combat shots and gate switches are cased for a level.
nonisolated enum CombatGraphemeCase: String, Codable, Equatable, Sendable, CaseIterable {
    case lower
    case upper
    case both

    /// Display form of a catalog grapheme id. Case is a separate draw from identity:
    /// multi-letter graphemes stay lowercase; single letters follow this mode.
    func displayLetter(
        for grapheme: String,
        rng: inout some RandomNumberGenerator
    ) -> String {
        let base = grapheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return base }
        let identity = base.lowercased()
        guard identity.count == 1 else { return identity }
        switch self {
        case .lower:
            return identity
        case .upper:
            return identity.uppercased()
        case .both:
            return Bool.random(using: &rng) ? identity : identity.uppercased()
        }
    }

    /// Unique lowercase grapheme ids. Case is not part of identity — apply
    /// `displayLetter(for:rng:)` after a grapheme has been chosen.
    func shotLetterPool(from letters: [String]) -> [String] {
        Self.identityIDs(from: letters)
    }

    /// Unique lowercase grapheme ids, first-seen order preserved.
    static func identityIDs(from letters: [String]) -> [String] {
        var seen = Set<String>()
        var bases: [String] = []
        for raw in letters {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            bases.append(id)
        }
        return bases
    }
}
