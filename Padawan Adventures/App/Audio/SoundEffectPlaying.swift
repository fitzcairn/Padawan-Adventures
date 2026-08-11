import AVFoundation
import Foundation

/// Minimal one-shot / loop player surface used by `SoundEffectsController` (mockable in tests).
@MainActor
protocol SoundEffectPlaying: AnyObject {
    /// Plays a short effect. Returns `false` when the track cannot be loaded.
    @discardableResult
    func play(trackID: String, volume: Float) -> Bool

    /// Plays a clip on the exclusive voice-over channel: whatever line is already
    /// playing there fades out over `crossfade` while this one fades in, so at most
    /// one voice-over is fully audible. Returns `false` when the track cannot be loaded.
    @discardableResult
    func playVoiceOver(trackID: String, volume: Float, crossfade: TimeInterval) -> Bool

    /// Clip length in seconds, or nil when the track cannot be resolved.
    func duration(of trackID: String) -> TimeInterval?

    /// Warms the clip pool for the given track ids without starting playback.
    func prepare(trackIDs: [String])

    /// Starts (or restarts) an indefinitely looping track. Returns `false` when it cannot be loaded.
    @discardableResult
    func startLoop(trackID: String, volume: Float) -> Bool

    func stopLoop(trackID: String)

    func stopAllLoops()

    /// Scales all active loop volumes (`1` = unducked base levels).
    func setLoopDuckScale(_ scale: Float)

    /// Fades playing one-shot instances of `trackID` to silence, then stops them.
    func fadeOutAndStop(trackID: String, duration: TimeInterval)

    /// Fades every playing one-shot and loop to silence, then stops them.
    func fadeOutAndStopAll(duration: TimeInterval)
}

/// Owns `AVAudioPlayer` instances so `deinit` can always stop them, even when
/// the outer `@MainActor` type tears down off the main actor in tests.
private final class SoundEffectPlayerStorage {
    var pools: [String: [AVAudioPlayer]] = [:]
    var loopPlayers: [String: AVAudioPlayer] = [:]
    /// Keyed by player instance, not track id, so the two pooled instances of one
    /// track can fade independently while they crossfade into each other.
    var oneShotFadeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    var loopFadeTask: Task<Void, Never>?

    func stopEverything() {
        for task in oneShotFadeTasks.values {
            task.cancel()
        }
        oneShotFadeTasks.removeAll()
        loopFadeTask?.cancel()
        loopFadeTask = nil
        for players in pools.values {
            for player in players {
                player.stop()
            }
        }
        pools.removeAll()
        for player in loopPlayers.values {
            player.stop()
        }
        loopPlayers.removeAll()
    }

    deinit {
        stopEverything()
    }
}

/// Bundle-backed per-track `AVAudioPlayer` pool for overlapping one-shots.
@MainActor
final class BundleSoundEffectPlayer: SoundEffectPlaying {
    private var urlCache: [String: URL] = [:]
    private let storage = SoundEffectPlayerStorage()
    private var trackOrder: [String] = []
    private var durationCache: [String: TimeInterval] = [:]
    private var loopBaseVolumes: [String: Float] = [:]
    private var loopDuckScale: Float = 1

    /// Simultaneous instances of the *same* effect before the oldest is retriggered.
    static let playersPerTrack = 2
    /// Distinct tracks held before the least-recently-used track is dropped.
    static let maxCachedTracks = 32

    /// Test seam: total `AVAudioPlayer` instances constructed since init.
    private(set) var decodeCount = 0
    /// Test seam: distinct tracks currently pooled.
    var cachedTrackCount: Int { storage.pools.count }
    /// Test seam: whether any pooled player is currently audible.
    var anyPooledPlayerIsPlaying: Bool {
        storage.pools.values.contains { players in players.contains(where: \.isPlaying) }
    }

    /// Stops every one-shot and loop immediately (also runs from storage `deinit`).
    func stopAll() {
        storage.stopEverything()
        trackOrder.removeAll()
        loopBaseVolumes.removeAll()
        loopDuckScale = 1
    }

    @discardableResult
    func play(trackID: String, volume: Float) -> Bool {
        // A new play supersedes any in-flight fade-out for this track.
        storage.oneShotFadeTasks[trackID]?.cancel()
        storage.oneShotFadeTasks[trackID] = nil
        guard let url = resolvedURL(for: trackID) else { return false }
        configureSessionIfNeeded()
        guard let player = pooledPlayer(for: trackID, url: url) else { return false }
        player.volume = min(1, max(0, volume))
        player.currentTime = 0
        return player.play()
    }

    func duration(of trackID: String) -> TimeInterval? {
        if let cached = durationCache[trackID] {
            return cached
        }
        guard let url = resolvedURL(for: trackID) else { return nil }
        configureSessionIfNeeded()
        guard let player = pooledPlayer(for: trackID, url: url) else { return nil }
        let value = player.duration
        durationCache[trackID] = value
        return value
    }

    func prepare(trackIDs: [String]) {
        for trackID in trackIDs {
            let trimmed = trackID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = resolvedURL(for: trimmed) else { continue }
            configureSessionIfNeeded()
            _ = pooledPlayer(for: trimmed, url: url)
        }
    }

    @discardableResult
    func startLoop(trackID: String, volume: Float) -> Bool {
        let clamped = min(1, max(0, volume))
        loopBaseVolumes[trackID] = clamped
        if let existing = storage.loopPlayers[trackID] {
            existing.volume = clamped * loopDuckScale
            if !existing.isPlaying {
                existing.currentTime = 0
                return existing.play()
            }
            return true
        }
        guard let url = resolvedURL(for: trackID) else { return false }
        configureSessionIfNeeded()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = clamped * loopDuckScale
            player.prepareToPlay()
            decodeCount += 1
            storage.loopPlayers[trackID] = player
            return player.play()
        } catch {
            return false
        }
    }

    func stopLoop(trackID: String) {
        guard let player = storage.loopPlayers.removeValue(forKey: trackID) else { return }
        loopBaseVolumes.removeValue(forKey: trackID)
        player.stop()
    }

    func stopAllLoops() {
        storage.loopFadeTask?.cancel()
        storage.loopFadeTask = nil
        for player in storage.loopPlayers.values {
            player.stop()
        }
        storage.loopPlayers.removeAll()
        loopBaseVolumes.removeAll()
        loopDuckScale = 1
    }

    func setLoopDuckScale(_ scale: Float) {
        loopDuckScale = min(1, max(0, scale))
        for (trackID, player) in storage.loopPlayers {
            let base = loopBaseVolumes[trackID] ?? player.volume
            player.volume = base * loopDuckScale
        }
    }

    func fadeOutAndStop(trackID: String, duration: TimeInterval) {
        storage.oneShotFadeTasks[trackID]?.cancel()
        storage.oneShotFadeTasks[trackID] = nil

        guard let pool = storage.pools[trackID] else { return }
        let playing = pool.filter(\.isPlaying)
        guard !playing.isEmpty else { return }

        if duration <= 0 {
            for player in playing {
                player.stop()
                player.currentTime = 0
            }
            return
        }

        let startVolumes = playing.map(\.volume)
        let task = Task { @MainActor in
            await VolumeFader.fadeOutMultiplicative(startVolume: 1, duration: duration) { scale in
                guard !Task.isCancelled else { return }
                for (player, start) in zip(playing, startVolumes) {
                    guard player.isPlaying else { continue }
                    player.volume = start * scale
                }
            }
            guard !Task.isCancelled else { return }
            for player in playing {
                player.stop()
                player.currentTime = 0
            }
            self.storage.oneShotFadeTasks[trackID] = nil
        }
        storage.oneShotFadeTasks[trackID] = task
    }

    func fadeOutAndStopAll(duration: TimeInterval) {
        for trackID in Array(storage.pools.keys) {
            fadeOutAndStop(trackID: trackID, duration: duration)
        }
        fadeOutAndStopAllLoops(duration: duration)
    }

    private func fadeOutAndStopAllLoops(duration: TimeInterval) {
        storage.loopFadeTask?.cancel()
        storage.loopFadeTask = nil

        let players = Array(storage.loopPlayers.values)
        guard !players.isEmpty else { return }

        // Detach so a new `startLoop` during the fade creates a fresh player.
        storage.loopPlayers.removeAll()
        loopBaseVolumes.removeAll()
        loopDuckScale = 1

        if duration <= 0 {
            for player in players {
                player.stop()
            }
            return
        }

        let startVolumes = players.map(\.volume)
        let task = Task { @MainActor in
            await VolumeFader.fadeOutMultiplicative(startVolume: 1, duration: duration) { scale in
                guard !Task.isCancelled else { return }
                for (player, start) in zip(players, startVolumes) {
                    guard player.isPlaying else { continue }
                    player.volume = start * scale
                }
            }
            guard !Task.isCancelled else { return }
            for player in players {
                player.stop()
            }
            self.storage.loopFadeTask = nil
        }
        storage.loopFadeTask = task
    }

    private func resolvedURL(for trackID: String) -> URL? {
        if let cached = urlCache[trackID] {
            return cached
        }
        guard let url = BundleMusicAudioPlayer.audioURL(
            for: trackID,
            subdirectories: AudioBundleLayout.fxSubdirectories + ["Audio"]
        ) else {
            return nil
        }
        urlCache[trackID] = url
        return url
    }

    private func pooledPlayer(for trackID: String, url: URL) -> AVAudioPlayer? {
        var pool = storage.pools[trackID] ?? []

        if let idle = pool.first(where: { !$0.isPlaying }) {
            touchTrackOrder(trackID)
            evictIfNeeded()
            return idle
        }

        if pool.count < Self.playersPerTrack {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = 0
                player.prepareToPlay()
                decodeCount += 1
                pool.append(player)
                storage.pools[trackID] = pool
                touchTrackOrder(trackID)
                evictIfNeeded()
                return player
            } catch {
                return nil
            }
        }

        let oldest = pool[0]
        oldest.stop()
        storage.pools[trackID] = pool
        touchTrackOrder(trackID)
        evictIfNeeded()
        return oldest
    }

    private func touchTrackOrder(_ trackID: String) {
        trackOrder.removeAll { $0 == trackID }
        trackOrder.append(trackID)
    }

    private func evictIfNeeded() {
        while trackOrder.count > Self.maxCachedTracks {
            let victim = trackOrder.removeFirst()
            if let players = storage.pools.removeValue(forKey: victim) {
                for player in players {
                    player.stop()
                }
            }
            durationCache[victim] = nil
        }
    }

    private func configureSessionIfNeeded() {
        AVAudioSessionConfigurator.configureAmbientIfNeeded()
    }
}
