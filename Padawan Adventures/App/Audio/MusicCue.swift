import Foundation

/// A background-music instruction parsed from YAML `music:` fields.
nonisolated enum MusicCue: Equatable, Sendable {
    /// Keep the currently playing track (YAML omitted, empty, or `none`).
    case unchanged
    /// Fade out and stay silent (`silence`).
    case silence
    /// Play the named bundle audio asset (basename without extension).
    case track(String)

    /// Parses a YAML `music:` value.
    nonisolated static func parse(_ raw: String?) -> MusicCue {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return .unchanged
        }
        switch trimmed.lowercased() {
        case "none":
            return .unchanged
        case "silence":
            return .silence
        default:
            return .track(trimmed)
        }
    }
}
