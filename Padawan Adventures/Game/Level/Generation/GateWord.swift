import Foundation

/// A shared vocabulary entry: optional illustration, pronunciation SFX, and grapheme breakdown.
nonisolated struct GateWord: Equatable, Sendable {
    var word: String
    /// Optional sprite basename under `Resources/Sprites/Words/` (no extension).
    var image: String?
    /// Full-word pronunciation track basename under `Resources/Audio/FX/Words/`.
    var sfx: String
    /// Ordered grapheme units that concatenate to `word` (e.g. `["st", "o", "p"]`).
    var graphemes: [String]

    /// Convenience for the full-word pronunciation track (open / auto-repeat).
    var sound: String { sfx }

    /// Legacy alias used by existing minigame engines; same as `sfx`.
    var spelling: String { sfx }

    /// Single-character letters of the word spelling (`Array(word)`).
    var letters: [String] { word.map { String($0) } }

    /// Lowercases words/graphemes, trims track names, and sorts by word for deterministic RNG.
    /// Grapheme order is preserved (spelling order is meaningful).
    static func normalized(_ words: [GateWord]) -> [GateWord] {
        words
            .map { entry in
                let image = entry.image?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let graphemes = entry.graphemes.compactMap { raw -> String? in
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return trimmed.isEmpty ? nil : trimmed
                }
                return GateWord(
                    word: entry.word.lowercased(),
                    image: (image?.isEmpty == false) ? image : nil,
                    sfx: entry.sfx.trimmingCharacters(in: .whitespacesAndNewlines),
                    graphemes: graphemes
                )
            }
            .sorted { $0.word < $1.word }
    }

    /// Per-character grapheme breakdown with derived full-word track.
    static func fallbackEntry(word: String, sfx: String? = nil) -> GateWord {
        let w = word.lowercased()
        let trimmedSfx = sfx?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let track = trimmedSfx.isEmpty ? "sfx_word_\(w)" : trimmedSfx
        return GateWord(
            word: w,
            image: nil,
            sfx: track,
            graphemes: w.map { String($0) }
        )
    }
}
