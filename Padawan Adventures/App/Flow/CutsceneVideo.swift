import AVFoundation

/// Session-scoped cutscene movie, built during bootstrap so the view can start
/// playback immediately instead of opening a cold file on screen.
@MainActor
final class CutsceneVideo {
    static let basename = "cutscene"
    static let subdirectory = "Backgrounds"

    private let bundle: Bundle
    private let effects: SoundEffectsController
    private(set) var player: AVPlayer?
    /// True while a skip fade is driving volume to zero; view teardown must not hard-cut.
    private(set) var isFadingOut = false
    private var fadeTask: Task<Void, Never>?
    private var fadeGeneration = 0

    init(bundle: Bundle = .main, effects: SoundEffectsController? = nil) {
        self.bundle = bundle
        self.effects = effects ?? .shared
    }

    static func url(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: basename, withExtension: "mp4", subdirectory: subdirectory)
    }

    /// Movie dialogue at `cutsceneVolumeScale` of the sound-effects level.
    ///
    /// The movie is speech, like the phonetic letter cues, so it belongs on the effects
    /// channel: silencing the score must not silence the story, and the cutscene screen
    /// mutes music anyway (`screens.yaml`), leaving no mix for it to sit over. Scaling
    /// down from a full-volume channel rather than boosting a quiet one also means the
    /// slider keeps working at the top of its range instead of running into a clamp.
    private var playbackVolume: Float {
        guard effects.soundEffectsEnabled else { return 0 }
        return effects.soundEffectsVolume * SoundEffectsController.cutsceneVolumeScale
    }

    /// Builds the player and waits briefly for the asset to become playable.
    func preload() async {
        guard player == nil, let url = Self.url(bundle: bundle) else { return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        // Hold the last frame instead of rewinding, so the end cue fires once.
        player.actionAtItemEnd = .pause
        // Local file: start on the first frame rather than buffering ahead.
        player.automaticallyWaitsToMinimizeStalling = false
        player.volume = playbackVolume
        self.player = player

        // Bounded so a bad asset can never stall the loading screen.
        for _ in 0..<40 {
            if item.status != .unknown { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Plays from the top; safe on a second new game in the same session.
    func restart() {
        cancelFade()
        guard let player else { return }
        player.volume = playbackVolume
        player.seek(to: .zero)
        player.play()
    }

    func stop() {
        cancelFade()
        guard let player else { return }
        player.pause()
        player.seek(to: .zero)
        player.volume = playbackVolume
    }

    /// Fades movie audio to silence over `duration`, then pauses and rewinds.
    /// Safe to call while the cutscene view is already crossfading away.
    func fadeOutAndStop(duration: TimeInterval = ScreenCrossFade.duration) async {
        guard let player else { return }
        fadeTask?.cancel()
        fadeGeneration += 1
        let generation = fadeGeneration
        isFadingOut = true
        let startVolume = player.volume

        let task = Task { @MainActor in
            await VolumeFader.fadeOutMultiplicative(
                startVolume: startVolume,
                duration: duration
            ) { volume in
                guard !Task.isCancelled else { return }
                player.volume = volume
            }
        }
        fadeTask = task
        await task.value

        // `stop()` / `restart()` bump the generation; leave their teardown alone.
        guard generation == fadeGeneration else { return }
        player.volume = 0
        player.pause()
        await player.seek(to: .zero)
        guard generation == fadeGeneration else { return }
        player.volume = playbackVolume
        isFadingOut = false
        fadeTask = nil
    }

    private func cancelFade() {
        fadeGeneration += 1
        fadeTask?.cancel()
        fadeTask = nil
        isFadingOut = false
    }
}
