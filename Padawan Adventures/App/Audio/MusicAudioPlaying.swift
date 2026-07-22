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

/// Bundle-backed looping `AVAudioPlayer` implementation.
@MainActor
final class BundleMusicAudioPlayer: MusicAudioPlaying {
    private(set) var currentTrackID: String?
    private var player: AVAudioPlayer?
    private var didConfigureSession = false

    var volume: Float {
        get { player?.volume ?? 0 }
        set { player?.volume = newValue }
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    func load(trackID: String) throws {
        guard let url = Self.audioURL(for: trackID, subdirectories: ["Audio/Music", "Audio"]) else {
            throw MusicConfigError.missingResource
        }
        configureSessionIfNeeded()
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.numberOfLoops = -1
        newPlayer.volume = 0
        newPlayer.prepareToPlay()
        player?.stop()
        player = newPlayer
        currentTrackID = trackID
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func stop() {
        player?.stop()
        player = nil
        currentTrackID = nil
    }

    func fadeVolume(to volume: Float, duration: TimeInterval) async {
        guard let player else { return }
        if duration <= 0 {
            player.volume = volume
            return
        }
        player.setVolume(volume, fadeDuration: duration)
        let nanos = UInt64(duration * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setActive(true)
    }

    static func audioURL(
        for trackID: String,
        subdirectories: [String] = ["Audio/Music", "Audio/FX", "Audio"]
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
