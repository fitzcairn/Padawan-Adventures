import AVFoundation
import Foundation

/// Minimal player surface used by `BackgroundMusicController` (mockable in tests).
@MainActor
protocol MusicAudioPlaying: AnyObject {
    var volume: Float { get set }
    var isPlaying: Bool { get }
    var currentTrackID: String? { get }

    func load(trackID: String) throws
    func play()
    func pause()
    func stop()
    /// Fades volume over `duration` seconds, then returns.
    func fadeVolume(to volume: Float, duration: TimeInterval) async
}

/// Bundle-backed streaming looping player (`AVQueuePlayer` + `AVPlayerLooper`).
@MainActor
final class BundleMusicAudioPlayer: MusicAudioPlaying {
    private(set) var currentTrackID: String?
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var fadeTask: Task<Void, Never>?
    private var fadeGeneration = 0

    var volume: Float {
        get { Float(queuePlayer?.volume ?? 0) }
        set {
            fadeGeneration += 1
            fadeTask?.cancel()
            fadeTask = nil
            queuePlayer?.volume = newValue
        }
    }

    var isPlaying: Bool {
        guard let queuePlayer else { return false }
        return queuePlayer.timeControlStatus == .playing || queuePlayer.rate > 0
    }

    func load(trackID: String) throws {
        guard let url = Self.audioURL(for: trackID, subdirectories: ["Audio/Music", "Audio"]) else {
            throw MusicConfigError.missingResource
        }
        configureSessionIfNeeded()
        tearDownPlayer()

        let player = AVQueuePlayer()
        player.volume = 0
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        currentTrackID = trackID
    }

    func play() {
        queuePlayer?.play()
    }

    func pause() {
        queuePlayer?.pause()
    }

    func stop() {
        tearDownPlayer()
        currentTrackID = nil
    }

    func fadeVolume(to volume: Float, duration: TimeInterval) async {
        fadeGeneration += 1
        let generation = fadeGeneration
        fadeTask?.cancel()
        fadeTask = nil

        guard let queuePlayer else { return }
        if duration <= 0 {
            queuePlayer.volume = volume
            return
        }

        let start = queuePlayer.volume
        let task = Task { @MainActor in
            await VolumeFader.linearFade(from: start, to: volume, duration: duration) { value in
                guard !Task.isCancelled, generation == self.fadeGeneration else { return }
                queuePlayer.volume = value
            }
            guard !Task.isCancelled, generation == self.fadeGeneration else { return }
            queuePlayer.volume = volume
        }
        fadeTask = task
        await task.value
        if generation == fadeGeneration {
            fadeTask = nil
        }
    }

    private func tearDownPlayer() {
        fadeGeneration += 1
        fadeTask?.cancel()
        fadeTask = nil
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer?.removeAllItems()
        queuePlayer = nil
    }

    private func configureSessionIfNeeded() {
        AudioSessionController.claimOutputIfNeeded()
    }

    static func audioURL(
        for trackID: String,
        subdirectories: [String] = AudioBundleLayout.musicSubdirectories
            + AudioBundleLayout.fxSubdirectories
            + ["Audio"]
    ) -> URL? {
        let extensions = ["m4a", "caf", "wav", "mp3"]
        for ext in extensions {
            for subdirectory in subdirectories {
                if let url = Bundle.main.url(
                    forResource: trackID,
                    withExtension: ext,
                    subdirectory: subdirectory
                ) {
                    return url
                }
            }
            if let url = Bundle.main.url(forResource: trackID, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
