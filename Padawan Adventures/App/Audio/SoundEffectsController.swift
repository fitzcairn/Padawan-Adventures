import Foundation

/// Process-lifetime owner of overlapping one-shot sound effects.
@MainActor
final class SoundEffectsController {
    static let shared = SoundEffectsController()

    private let player: any SoundEffectPlaying

    init(player: (any SoundEffectPlaying)? = nil) {
        self.player = player ?? BundleSoundEffectPlayer()
    }

    /// Plays a track by basename under `Resources/Audio/`. Missing assets are ignored.
    func play(trackID: String) {
        let trimmed = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = player.play(trackID: trimmed)
    }

    /// Looks up `event` in `table` and plays it. Unmapped events and missing assets are ignored.
    func play(event: String, from table: SoundEffectTable) {
        guard let trackID = table.trackID(for: event) else { return }
        play(trackID: trackID)
    }
}
