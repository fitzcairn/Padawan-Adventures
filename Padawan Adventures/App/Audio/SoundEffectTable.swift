import Foundation

/// Event-key → track-basename map (`Resources/Audio/<id>.m4a`, etc.).
nonisolated struct SoundEffectTable: Codable, Equatable, Sendable {
    var events: [String: String]

    nonisolated static let empty = SoundEffectTable(events: [:])

    init(events: [String: String] = [:]) {
        self.events = events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        events = try container.decode([String: String].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(events)
    }

    func trackID(for event: String) -> String? {
        guard let raw = events[event]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    /// Returns a copy of this table with `overrides` applied (per-event replace).
    func merging(_ overrides: SoundEffectTable) -> SoundEffectTable {
        guard !overrides.events.isEmpty else { return self }
        var merged = events
        for (event, trackID) in overrides.events {
            merged[event] = trackID
        }
        return SoundEffectTable(events: merged)
    }
}
