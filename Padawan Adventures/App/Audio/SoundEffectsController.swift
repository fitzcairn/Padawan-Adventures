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
        if !enabled {
            stopAllLoops()
        }
    }

    func setSoundEffectsVolume(_ volume: Float) {
        soundEffectsVolume = min(1, max(0, volume))
    }

    func configure(commonFx: SoundEffectTable) {
        self.commonFx = commonFx
    }

    /// Warms the clip pool for the given track ids without starting playback.
    func prepare(trackIDs: [String]) {
        player.prepare(trackIDs: trackIDs)
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

    /// Starts an indefinitely looping ambience track (lightsaber hum, gate arc).
    func startLoop(trackID: String) {
        guard soundEffectsEnabled else { return }
        let trimmed = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        player.startLoop(trackID: trimmed, volume: soundEffectsVolume)
    }

    /// Looks up `event` in `table` and starts it as a loop. Returns the track id so
    /// the caller can stop the exact track it started.
    @discardableResult
    func startLoop(event: String, from table: SoundEffectTable) -> String? {
        guard let trackID = table.trackID(for: event) else { return nil }
        startLoop(trackID: trackID)
        return trackID
    }

    func stopLoop(trackID: String?) {
        guard let trimmed = trackID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return }
        player.stopLoop(trackID: trimmed)
    }

    func stopAllLoops() {
        player.stopAllLoops()
    }

    /// Clip length, or nil for a blank or unresolvable track.
    func duration(of trackID: String?) -> TimeInterval? {
        guard let trimmed = trackID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return player.duration(of: trimmed)
    }

    /// Clip length for timing a follow-up action, with the puzzle scenes' historic
    /// 0.7s fallback and 0.35s floor.
    func cueDuration(of trackID: String?) -> TimeInterval {
        max(duration(of: trackID) ?? 0.7, 0.35)
    }
}
