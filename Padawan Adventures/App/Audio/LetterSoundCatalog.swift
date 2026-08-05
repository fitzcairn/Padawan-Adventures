import Foundation

/// Shared letter name / pronunciation track basenames used across minigames.
nonisolated enum LetterSoundCatalog {
    /// `sfx_grapheme_<lower>_name` for a single letter (e.g. `"B"` → `sfx_grapheme_b_name`).
    static func nameTrackID(for letter: String) -> String? {
        trackID(for: letter, suffix: "name")
    }

    /// `sfx_grapheme_<lower>_pronunciation` for a single letter.
    static func pronunciationTrackID(for letter: String) -> String? {
        trackID(for: letter, suffix: "pronunciation")
    }

    private static func trackID(for letter: String, suffix: String) -> String? {
        let trimmed = letter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.unicodeScalars.first,
              CharacterSet.letters.contains(scalar) else {
            return nil
        }
        let lower = String(scalar).lowercased()
        return "sfx_grapheme_\(lower)_\(suffix)"
    }
}
