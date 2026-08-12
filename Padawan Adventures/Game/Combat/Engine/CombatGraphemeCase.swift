import Foundation

/// How grapheme-sound combat shots and gate switches are cased for a level.
nonisolated enum CombatGraphemeCase: String, Codable, Equatable, Sendable, CaseIterable {
    case lower
    case upper
    case both

    /// Display form of one catalog grapheme id for this case mode.
    func displayLetter(
        for grapheme: String,
        rng: inout some RandomNumberGenerator
    ) -> String {
        let base = grapheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return base }
        switch self {
        case .lower:
            return base.lowercased()
        case .upper:
            return base.uppercased()
        case .both:
            return Bool.random(using: &rng) ? base.lowercased() : base.uppercased()
        }
    }

    /// Expands catalog letter ids into the visual/cue pool for this case mode.
    func shotLetterPool(from letters: [String]) -> [String] {
        var seen = Set<String>()
        var bases: [String] = []
        for raw in letters {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            bases.append(id)
        }
        switch self {
        case .lower:
            return bases
        case .upper:
            return bases.map { $0.uppercased() }
        case .both:
            return bases.flatMap { [$0.lowercased(), $0.uppercased()] }
        }
    }
}
