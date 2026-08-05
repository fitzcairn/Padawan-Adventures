import Foundation

/// How combat projectile / cue letters are cased for a level.
nonisolated enum CombatGraphemeCase: String, Codable, Equatable, Sendable, CaseIterable {
    case lower
    case upper
    case both

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
