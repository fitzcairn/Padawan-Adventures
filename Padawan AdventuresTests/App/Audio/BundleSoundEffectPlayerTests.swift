import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct BundleSoundEffectPlayerTests {
    @Test func retriggeringOneTrackIsBounded() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        for _ in 0..<5 {
            #expect(player.play(trackID: "win", volume: 1))
        }
        #expect(player.decodeCount >= 1)
        #expect(player.decodeCount <= 2)
        #expect(player.cachedTrackCount == 1)
    }

    @Test func distinctTracksGetSeparatePools() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.play(trackID: "win", volume: 1))
        #expect(player.play(trackID: "error", volume: 1))
        #expect(player.play(trackID: "correct", volume: 1))
        #expect(player.cachedTrackCount == 3)
        #expect(player.decodeCount == 3)
    }

    @Test func trackCacheIsBounded() throws {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        var trackIDs: [String] = []
        let graphemes = try GraphemeCatalog.loadFromBundle()
        for grapheme in graphemes.graphemes {
            trackIDs.append(grapheme.name)
            trackIDs.append(grapheme.pronunciation)
        }
        let words = try WordCatalog.loadFromBundle()
        for word in words.words {
            trackIDs.append(word.spelling)
        }
        let audio = try SoundSettings.loadFromBundle()
        trackIDs.append(contentsOf: audio.fx.events.values)
        trackIDs = Array(Set(trackIDs)).sorted()
        #expect(trackIDs.count > BundleSoundEffectPlayer.maxCachedTracks)

        // Warm the LRU via prepare — playing every catalog clip at once floods
        // CoreAudio and races teardown callbacks across parallel test clones.
        player.prepare(trackIDs: trackIDs)
        #expect(player.cachedTrackCount == BundleSoundEffectPlayer.maxCachedTracks)
        #expect(player.anyPooledPlayerIsPlaying == false)
    }

    @Test func missingTrackReturnsFalseWithoutCaching() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.play(trackID: "definitely_missing_sfx_xyz", volume: 1) == false)
        #expect(player.decodeCount == 0)
        #expect(player.cachedTrackCount == 0)
    }

    @Test func voiceOverWithoutCrossfadeStopsThePreviousLineOutright() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.playVoiceOver(trackID: "win", volume: 1, crossfade: 0))
        #expect(player.playVoiceOver(trackID: "error", volume: 1, crossfade: 0))
        #expect(player.isPlaying(trackID: "win") == false)
        #expect(player.audiblePlayerCount == 1)
    }

    @Test func voiceOverCrossfadeStartsTheNewLineFromSilence() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.playVoiceOver(trackID: "win", volume: 1, crossfade: 0.1))
        #expect(player.playVoiceOver(trackID: "error", volume: 1, crossfade: 0.1))
        // The two lines overlap only for the fade window: the outgoing one is still
        // at full level and the incoming one ramps up from silence.
        #expect(player.audiblePlayerCount == 2)
        #expect(player.audibleVolumes(of: "win") == [1])
        #expect(player.audibleVolumes(of: "error") == [0])
    }

    @Test func voiceOverCrossfadeSilencesThePreviousLine() async {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.playVoiceOver(trackID: "win", volume: 1, crossfade: 0.1))
        #expect(player.playVoiceOver(trackID: "error", volume: 1, crossfade: 0.1))
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(player.isPlaying(trackID: "win") == false)
    }

    /// Re-tapping the same line crossfades into a second instance rather than stacking.
    @Test func repeatingOneVoiceOverLineUsesTheSpareInstance() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.playVoiceOver(trackID: "win", volume: 1, crossfade: 0.1))
        #expect(player.playVoiceOver(trackID: "win", volume: 1, crossfade: 0.1))
        #expect(player.decodeCount == 2)
        #expect(player.audibleVolumes(of: "win").sorted() == [0, 1])
    }

    @Test func fadeOutVoiceOverLeavesOtherEffectsPlaying() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.playVoiceOver(trackID: "win", volume: 1, crossfade: 0.1))
        #expect(player.play(trackID: "error", volume: 1))
        player.fadeOutVoiceOver(duration: 0)
        #expect(player.isPlaying(trackID: "win") == false)
        #expect(player.isPlaying(trackID: "error"))
    }

    @Test func fadeOutVoiceOverStopsTheLineAfterTheFade() async {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.playVoiceOver(trackID: "win", volume: 1, crossfade: 0.1))
        player.fadeOutVoiceOver(duration: 0.1)
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(player.isPlaying(trackID: "win") == false)
    }

    /// One-shot FX keep overlapping — exclusivity is only for the voice-over channel.
    @Test func oneShotsStillOverlap() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        #expect(player.play(trackID: "win", volume: 1))
        #expect(player.play(trackID: "error", volume: 1))
        #expect(player.audiblePlayerCount == 2)
    }

    @Test func durationDoesNotStartPlayback() {
        let player = BundleSoundEffectPlayer()
        defer { player.stopAll() }
        let duration = player.duration(of: "win")
        #expect(duration != nil)
        #expect((duration ?? 0) > 0)
        #expect(player.anyPooledPlayerIsPlaying == false)
    }
}
