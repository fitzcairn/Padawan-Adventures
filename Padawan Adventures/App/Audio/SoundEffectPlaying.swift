import AVFoundation
import Foundation

/// Minimal one-shot player surface used by `SoundEffectsController` (mockable in tests).
@MainActor
protocol SoundEffectPlaying: AnyObject {
    /// Plays a short effect. Returns `false` when the track cannot be loaded.
    @discardableResult
    func play(trackID: String, volume: Float) -> Bool
}

/// Bundle-backed multi-channel `AVAudioPlayer` pool for overlapping one-shots.
@MainActor
final class BundleSoundEffectPlayer: SoundEffectPlaying {
    private let channelCount: Int
    private var players: [AVAudioPlayer] = []
    private var nextSlot = 0
    private var didConfigureSession = false

    init(channelCount: Int = 8) {
        self.channelCount = max(1, channelCount)
    }

    @discardableResult
    func play(trackID: String, volume: Float) -> Bool {
        guard let url = BundleMusicAudioPlayer.audioURL(
            for: trackID,
            subdirectories: ["Audio/FX", "Audio"]
        ) else {
            return false
        }
        configureSessionIfNeeded()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = min(1, max(0, volume))
            player.prepareToPlay()
            insert(player)
            return player.play()
        } catch {
            return false
        }
    }

    private func insert(_ player: AVAudioPlayer) {
        if players.count < channelCount {
            players.append(player)
            return
        }
        let index = nextSlot % channelCount
        nextSlot = (index + 1) % channelCount
        players[index].stop()
        players[index] = player
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [])
        try? session.setActive(true)
    }
}
