import CoreGraphics
import Foundation

/// Pure helpers for the word rendered on a deflect-arena orb.
nonisolated enum CombatDeflectOrbWord {
    /// The word split into display units, with the answer grapheme replaced by one
    /// blank box per character (`stop` + `st` starting -> `["_", "_", "o", "p"]`).
    /// Mirrors `GateWordPlugLetterPosition.maskedText(for:)` but works from the
    /// grapheme string the scene already has instead of a full `GateWord`.
    static func maskedUnits(
        word: String,
        grapheme: String,
        position: GateWordPlugLetterPosition
    ) -> [String] {
        let word = word.lowercased()
        let count = grapheme.count
        guard count > 0, count <= word.count else { return word.map(String.init) }
        let blanks = [String](repeating: "_", count: count)
        switch position {
        case .starting: return blanks + word.dropFirst(count).map(String.init)
        case .ending: return word.dropLast(count).map(String.init) + blanks
        }
    }

    /// Projectile art width for a word row of `wordWidth`, plus the scale to apply to
    /// that row. The art grows so the word occupies `fitFraction` of it, never shrinks
    /// below `baseWidth`, and never exceeds `maxWidth` — a word too long for the cap is
    /// scaled down instead.
    static func fit(
        wordWidth: CGFloat,
        baseWidth: CGFloat,
        maxWidth: CGFloat,
        fitFraction: CGFloat
    ) -> (projectileWidth: CGFloat, wordScale: CGFloat) {
        let cap = max(maxWidth, 1)
        let base = min(max(baseWidth, 1), cap)
        let fraction = min(max(fitFraction, 0.05), 1)
        let needed = max(wordWidth, 0) / fraction
        let width = min(max(base, needed), cap)
        let allowed = width * fraction
        let scale = wordWidth > allowed ? allowed / max(wordWidth, 1) : 1
        return (width, scale)
    }
}
