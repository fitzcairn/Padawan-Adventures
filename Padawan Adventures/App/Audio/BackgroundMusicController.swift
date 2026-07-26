import Foundation

/// Process-lifetime owner of background music playback and crossfades.
@MainActor
final class BackgroundMusicController {
    static let shared = BackgroundMusicController()

    private(set) var fadeSeconds: TimeInterval = SoundSettings.fallback.fadeSeconds
    private(set) var currentTrackID: String?
    private(set) var isPausedForBackground = false
    private(set) var musicEnabled = true
    private(set) var musicVolume: Float = 1

    private let player: any MusicAudioPlaying
    private var transitionTask: Task<Void, Never>?
    private var transitionGeneration = 0

    var effectiveVolume: Float {
        musicEnabled ? musicVolume : 0
    }

    init(player: (any MusicAudioPlaying)? = nil) {
        self.player = player ?? BundleMusicAudioPlayer()
    }

    func configure(fadeSeconds: TimeInterval) {
        self.fadeSeconds = max(0, fadeSeconds)
    }

    func setMusicEnabled(_ enabled: Bool) {
        guard musicEnabled != enabled else { return }
        musicEnabled = enabled
        applyEffectiveVolumeLive()
    }

    func setMusicVolume(_ volume: Float) {
        let clamped = min(1, max(0, volume))
        guard musicVolume != clamped else { return }
        musicVolume = clamped
        applyEffectiveVolumeLive()
    }

    /// Loads `Resources/Config/Screens/<name>.yaml` and applies its music cue.
    func applyScreen(named name: String) {
        let cue: MusicCue
        if let config = try? ScreenConfig.loadFromBundle(named: name) {
            cue = config.musicCue
        } else {
            cue = .unchanged
        }
        apply(cue)
    }

    func apply(_ cue: MusicCue) {
        switch cue {
        case .unchanged:
            return
        case .silence:
            beginTransition { [weak self] in
                await self?.fadeOutAndClear()
            }
        case .track(let trackID):
            if trackID == currentTrackID, player.isPlaying || isPausedForBackground {
                return
            }
            beginTransition { [weak self] in
                await self?.fadeToTrack(trackID)
            }
        }
    }

    func pauseForBackground() {
        guard !isPausedForBackground else { return }
        isPausedForBackground = true
        player.pause()
    }

    func resumeFromBackground() {
        guard isPausedForBackground else { return }
        isPausedForBackground = false
        if currentTrackID != nil {
            player.play()
        }
    }

    // MARK: - Transitions

    private func beginTransition(_ work: @escaping @MainActor () async -> Void) {
        transitionGeneration += 1
        let generation = transitionGeneration
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            await work()
            guard !Task.isCancelled, generation == self.transitionGeneration else { return }
        }
    }

    private var halfFade: TimeInterval {
        fadeSeconds / 2
    }

    private func applyEffectiveVolumeLive() {
        guard currentTrackID != nil else { return }
        player.volume = effectiveVolume
    }

    private func fadeOutAndClear() async {
        if player.isPlaying || player.currentTrackID != nil {
            await player.fadeVolume(to: 0, duration: halfFade)
            guard !Task.isCancelled else { return }
            player.stop()
        }
        currentTrackID = nil
    }

    private func fadeToTrack(_ trackID: String) async {
        if player.currentTrackID != nil {
            await player.fadeVolume(to: 0, duration: halfFade)
            guard !Task.isCancelled else { return }
            player.stop()
        }

        do {
            try player.load(trackID: trackID)
        } catch {
            currentTrackID = nil
            return
        }

        guard !Task.isCancelled else { return }

        if isPausedForBackground {
            currentTrackID = trackID
            player.volume = effectiveVolume
            return
        }

        player.volume = 0
        player.play()
        currentTrackID = trackID
        await player.fadeVolume(to: effectiveVolume, duration: halfFade)
    }
}
