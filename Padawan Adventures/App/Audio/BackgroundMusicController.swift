import Foundation

/// Process-lifetime owner of background music playback and crossfades.
@MainActor
final class BackgroundMusicController {
    static let shared = BackgroundMusicController()

    private(set) var fadeSeconds: TimeInterval = SoundSettings.fallback.fadeSeconds
    private(set) var currentTrackID: String?
    private(set) var isPausedForBackground = false
    private(set) var musicEnabled = true
    private(set) var musicVolume: Float = PlayerSettings.defaultMusicVolume

    /// Ducks music so phonetic cues at `phoneticVolumeScale` stay ~20% clearer in the mix.
    static let musicMixScale: Float = 1 / SoundEffectsController.phoneticVolumeScale

    private let player: any MusicAudioPlaying
    private var transitionTask: Task<Void, Never>?
    private var transitionGeneration = 0
    private var phoneticDuckTask: Task<Void, Never>?
    private var phoneticDuckGeneration = 0
    private(set) var isPhoneticDucked = false

    var effectiveVolume: Float {
        let base = musicEnabled ? musicVolume * Self.musicMixScale : 0
        return isPhoneticDucked ? base * SoundEffectsController.phoneticCueDuckScale : base
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

    /// Loads `screens.<name>` from `Resources/Config/screens.yaml` and applies its music cue.
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

    /// Temporarily ducks music under a phonetic cue, then restores. Overlapping cues
    /// extend the duck window from the latest call.
    func duckForPhoneticCue(duration: TimeInterval) {
        let hold = max(duration, 0.05)
        phoneticDuckGeneration += 1
        let generation = phoneticDuckGeneration
        phoneticDuckTask?.cancel()
        isPhoneticDucked = true
        applyEffectiveVolumeLive()

        phoneticDuckTask = Task { @MainActor in
            let nanos = UInt64(hold * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, generation == self.phoneticDuckGeneration else { return }
            self.isPhoneticDucked = false
            self.phoneticDuckTask = nil
            self.applyEffectiveVolumeLive()
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
