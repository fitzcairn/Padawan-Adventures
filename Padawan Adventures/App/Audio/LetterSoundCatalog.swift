import Foundation

/// Shared letter/grapheme name / pronunciation track basenames used across minigames.
nonisolated enum LetterSoundCatalog {
    /// Name track for a grapheme (`sfx_letter_b_name` or `sfx_grapheme_sh_name`).
    static func nameTrackID(for letter: String) -> String? {
        trackID(for: letter, suffix: "name")
    }

    /// Pronunciation track for a grapheme.
    static func pronunciationTrackID(for letter: String) -> String? {
        trackID(for: letter, suffix: "pronunciation")
    }

    private static func trackID(for letter: String, suffix: String) -> String? {
        let trimmed = letter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else {
            return nil
        }
        let lower = trimmed.lowercased()
        let prefix = lower.count == 1 ? "sfx_letter" : "sfx_grapheme"
        return "\(prefix)_\(lower)_\(suffix)"
    }
}
