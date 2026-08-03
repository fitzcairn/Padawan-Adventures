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
