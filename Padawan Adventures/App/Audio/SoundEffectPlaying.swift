import AVFoundation
import Foundation

/// Minimal one-shot / loop player surface used by `SoundEffectsController` (mockable in tests).
@MainActor
protocol SoundEffectPlaying: AnyObject {
    /// Plays a short effect. Returns `false` when the track cannot be loaded.
    @discardableResult
    func play(trackID: String, volume: Float) -> Bool

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

/// Bundle-backed per-track `AVAudioPlayer` pool for overlapping one-shots.
@MainActor
final class BundleSoundEffectPlayer: SoundEffectPlaying {
    private var urlCache: [String: URL] = [:]
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var trackOrder: [String] = []
    private var durationCache: [String: TimeInterval] = [:]
    /// Separate from the one-shot LRU pool so loops are never evicted mid-play.
    private var loopPlayers: [String: AVAudioPlayer] = [:]
    private var loopBaseVolumes: [String: Float] = [:]
    private var loopDuckScale: Float = 1
    private var oneShotFadeTasks: [String: Task<Void, Never>] = [:]
    private var loopFadeTask: Task<Void, Never>?

    /// Simultaneous instances of the *same* effect before the oldest is retriggered.
    static let playersPerTrack = 2
    /// Distinct tracks held before the least-recently-used track is dropped.
    static let maxCachedTracks = 32

    /// Test seam: total `AVAudioPlayer` instances constructed since init.
    private(set) var decodeCount = 0
    /// Test seam: distinct tracks currently pooled.
    var cachedTrackCount: Int { pools.count }
    /// Test seam: whether any pooled player is currently audible.
    var anyPooledPlayerIsPlaying: Bool {
        pools.values.contains { players in players.contains(where: \.isPlaying) }
    }

    @discardableResult
    func play(trackID: String, volume: Float) -> Bool {
        // A new play supersedes any in-flight fade-out for this track.
        oneShotFadeTasks[trackID]?.cancel()
        oneShotFadeTasks[trackID] = nil
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
        if let existing = loopPlayers[trackID] {
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
            loopPlayers[trackID] = player
            return player.play()
        } catch {
            return false
        }
    }

    func stopLoop(trackID: String) {
        guard let player = loopPlayers.removeValue(forKey: trackID) else { return }
        loopBaseVolumes.removeValue(forKey: trackID)
        player.stop()
    }

    func stopAllLoops() {
        loopFadeTask?.cancel()
        loopFadeTask = nil
        for player in loopPlayers.values {
            player.stop()
        }
        loopPlayers.removeAll()
        loopBaseVolumes.removeAll()
        loopDuckScale = 1
    }

    func setLoopDuckScale(_ scale: Float) {
        loopDuckScale = min(1, max(0, scale))
        for (trackID, player) in loopPlayers {
            let base = loopBaseVolumes[trackID] ?? player.volume
            player.volume = base * loopDuckScale
        }
    }

    func fadeOutAndStop(trackID: String, duration: TimeInterval) {
        oneShotFadeTasks[trackID]?.cancel()
        oneShotFadeTasks[trackID] = nil

        guard let pool = pools[trackID] else { return }
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
            self.oneShotFadeTasks[trackID] = nil
        }
        oneShotFadeTasks[trackID] = task
    }

    func fadeOutAndStopAll(duration: TimeInterval) {
        for trackID in Array(pools.keys) {
            fadeOutAndStop(trackID: trackID, duration: duration)
        }
        fadeOutAndStopAllLoops(duration: duration)
    }

    private func fadeOutAndStopAllLoops(duration: TimeInterval) {
        loopFadeTask?.cancel()
        loopFadeTask = nil

        let players = Array(loopPlayers.values)
        guard !players.isEmpty else { return }

        // Detach so a new `startLoop` during the fade creates a fresh player.
        loopPlayers.removeAll()
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
            self.loopFadeTask = nil
        }
        loopFadeTask = task
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
        var pool = pools[trackID] ?? []

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
                pools[trackID] = pool
                touchTrackOrder(trackID)
                evictIfNeeded()
                return player
            } catch {
                return nil
            }
        }

        let oldest = pool[0]
        oldest.stop()
        pools[trackID] = pool
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
            if let players = pools.removeValue(forKey: victim) {
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
