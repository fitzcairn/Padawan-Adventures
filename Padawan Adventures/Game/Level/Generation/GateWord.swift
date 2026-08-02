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

    static func fallbackEntry(word: String, fxPrefix: String = "sfx_word_") -> GateWord {
        let w = word.lowercased()
        let prefixBase = fxPrefix.isEmpty ? "sfx_word_" : fxPrefix
        var progressive: [String: String] = [:]
        var prefix = ""
        for character in w {
            prefix.append(character)
            progressive[prefix] = "\(prefixBase)\(w)_\(prefix)"
        }
        return GateWord(
            word: w,
            image: nil,
            sfx: "\(prefixBase)\(w)",
            progressive: progressive
        )
    }
}
