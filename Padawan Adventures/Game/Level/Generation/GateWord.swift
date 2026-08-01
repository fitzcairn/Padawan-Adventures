import Foundation

/// A shared / gate vocabulary entry: spelling track + progressive prefix tracks.
nonisolated struct GateWord: Equatable, Sendable {
    var word: String
    /// Full spelling cue, e.g. "s, t, a, r. Star".
    var spelling: String
    /// Prefix → track basename (`s`, `st`, `sta`, `star`, …).
    var progressive: [String: String]

    /// Convenience for the full-word spelling track (open / auto-repeat).
    var sound: String { spelling }

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
        return GateWord(word: w, spelling: "\(prefixBase)\(w)", progressive: progressive)
    }
}
