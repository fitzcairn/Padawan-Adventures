import Foundation

/// Process-lifetime owner of overlapping one-shot sound effects.
@MainActor
final class SoundEffectsController {
    static let shared = SoundEffectsController()

    private(set) var soundEffectsEnabled = true
    private(set) var soundEffectsVolume: Float = 1
    /// Shared FX from `sound.yaml` (`win`, `lose`, `error`, `correct`, …).
    private(set) var commonFx: SoundEffectTable = SoundSettings.fallback.fx

    private let player: any SoundEffectPlaying

    init(player: (any SoundEffectPlaying)? = nil) {
        self.player = player ?? BundleSoundEffectPlayer()
    }

    func setSoundEffectsEnabled(_ enabled: Bool) {
        soundEffectsEnabled = enabled
    }

    func setSoundEffectsVolume(_ volume: Float) {
        soundEffectsVolume = min(1, max(0, volume))
    }

    func configure(commonFx: SoundEffectTable) {
        self.commonFx = commonFx
    }

    /// Plays a track by basename under `Resources/Audio/FX/`. Missing assets are ignored.
    func play(trackID: String) {
        guard soundEffectsEnabled else { return }
        let trimmed = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = player.play(trackID: trimmed, volume: soundEffectsVolume)
    }

    /// Looks up `event` in `table` and plays it. Unmapped events and missing assets are ignored.
    func play(event: String, from table: SoundEffectTable) {
        guard let trackID = table.trackID(for: event) else { return }
        play(trackID: trackID)
    }

    /// Plays a shared event from `sound.yaml` (`win`, `lose`, `error`, `correct`, …).
    /// When `override` is a non-empty track basename, that track is used instead.
    func playCommon(event: String, override: String? = nil) {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            play(trackID: override)
            return
        }
        play(event: event, from: commonFx)
    }
}
