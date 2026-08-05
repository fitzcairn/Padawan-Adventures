import Foundation

/// A shared vocabulary entry: optional illustration, pronunciation SFX, and progressive prefix tracks.
nonisolated struct GateWord: Equatable, Sendable {
    var word: String
    /// Optional sprite basename under `Resources/Sprites/Words/` (no extension).
    var image: String?
    /// Full-word pronunciation track basename under `Resources/Audio/FX/Words/`.
    var sfx: String
    /// Prefix → track basename (`s`, `st`, `sta`, `star`, …).
    var progressive: [String: String]

    /// Convenience for the full-word pronunciation track (open / auto-repeat).
    var sound: String { sfx }

    /// Legacy alias used by existing minigame engines; same as `sfx`.
    var spelling: String { sfx }

    func progressiveTrack(forPrefix prefix: String) -> String? {
        let key = prefix.lowercased()
        guard let track = progressive[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !track.isEmpty else {
            return nil
        }
        return track
    }

    /// Lowercases words/prefix keys, trims track names, and sorts by word for deterministic RNG.
    static func normalized(_ words: [GateWord]) -> [GateWord] {
        words
            .map { entry in
                var progressive: [String: String] = [:]
                for (key, value) in entry.progressive {
                    progressive[key.lowercased()] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let image = entry.image?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return GateWord(
                    word: entry.word.lowercased(),
                    image: (image?.isEmpty == false) ? image : nil,
                    sfx: entry.sfx.trimmingCharacters(in: .whitespacesAndNewlines),
                    progressive: progressive
                )
            }
            .sorted { $0.word < $1.word }
    }

    /// Builds progressive prefix tracks as `<sfx>_<prefix>` (e.g. `sfx_word_star_st`).
    static func fallbackEntry(word: String, sfx: String? = nil) -> GateWord {
        let w = word.lowercased()
        let trimmedSfx = sfx?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let track = trimmedSfx.isEmpty ? "sfx_word_\(w)" : trimmedSfx
        var progressive: [String: String] = [:]
        var prefix = ""
        for character in w {
            prefix.append(character)
            progressive[prefix] = "\(track)_\(prefix)"
        }
        return GateWord(
            word: w,
            image: nil,
            sfx: track,
            progressive: progressive
        )
    }
}
