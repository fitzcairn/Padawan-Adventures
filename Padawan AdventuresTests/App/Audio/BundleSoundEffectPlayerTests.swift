import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct BundleSoundEffectPlayerTests {
    @Test func retriggeringOneTrackIsBounded() {
        let player = BundleSoundEffectPlayer()
        for _ in 0..<5 {
            #expect(player.play(trackID: "win", volume: 1))
        }
        #expect(player.decodeCount >= 1)
        #expect(player.decodeCount <= 2)
        #expect(player.cachedTrackCount == 1)
    }

    @Test func distinctTracksGetSeparatePools() {
        let player = BundleSoundEffectPlayer()
        #expect(player.play(trackID: "win", volume: 1))
        #expect(player.play(trackID: "error", volume: 1))
        #expect(player.play(trackID: "correct", volume: 1))
        #expect(player.cachedTrackCount == 3)
        #expect(player.decodeCount == 3)
    }

    @Test func trackCacheIsBounded() throws {
        let player = BundleSoundEffectPlayer()
        var trackIDs: [String] = []
        let letters = try LetterCatalog.loadFromBundle()
        for letter in letters.letters {
            trackIDs.append(letter.name)
            trackIDs.append(letter.pronunciation)
        }
        let words = try WordCatalog.loadFromBundle()
        for word in words.words {
            trackIDs.append(word.spelling)
            trackIDs.append(contentsOf: word.progressive.values)
        }
        let audio = try SoundSettings.loadFromBundle()
        trackIDs.append(contentsOf: audio.fx.events.values)
        trackIDs = Array(Set(trackIDs)).sorted()
        #expect(trackIDs.count > BundleSoundEffectPlayer.maxCachedTracks)

        for trackID in trackIDs {
            _ = player.play(trackID: trackID, volume: 1)
        }
        #expect(player.cachedTrackCount == BundleSoundEffectPlayer.maxCachedTracks)
    }

    @Test func missingTrackReturnsFalseWithoutCaching() {
        let player = BundleSoundEffectPlayer()
        #expect(player.play(trackID: "definitely_missing_sfx_xyz", volume: 1) == false)
        #expect(player.decodeCount == 0)
        #expect(player.cachedTrackCount == 0)
    }

    @Test func durationDoesNotStartPlayback() {
        let player = BundleSoundEffectPlayer()
        let duration = player.duration(of: "win")
        #expect(duration != nil)
        #expect((duration ?? 0) > 0)
        #expect(player.anyPooledPlayerIsPlaying == false)
    }
}
