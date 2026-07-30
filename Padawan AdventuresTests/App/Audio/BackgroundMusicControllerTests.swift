import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
final class MockMusicAudioPlayer: MusicAudioPlaying {
    var volume: Float = 0
    var isPlaying = false
    private(set) var currentTrackID: String?
    private(set) var loadCalls: [String] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var fadeCalls: [(Float, TimeInterval)] = []
    var failNextLoad = false

    func load(trackID: String) throws {
        if failNextLoad {
            failNextLoad = false
            throw MusicConfigError.missingResource
        }
        loadCalls.append(trackID)
        currentTrackID = trackID
        volume = 0
        isPlaying = false
    }

    func play() {
        playCount += 1
        isPlaying = true
    }

    func pause() {
        pauseCount += 1
        isPlaying = false
    }

    func stop() {
        stopCount += 1
        isPlaying = false
        currentTrackID = nil
        volume = 0
    }

    func fadeVolume(to volume: Float, duration: TimeInterval) async {
        fadeCalls.append((volume, duration))
        self.volume = volume
    }
}

@MainActor
struct BackgroundMusicControllerTests {
    @Test func unchangedDoesNothing() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        controller.apply(.unchanged)
        // Allow any accidental task to settle.
        await Task.yield()
        #expect(mock.loadCalls.isEmpty)
        #expect(mock.playCount == 0)
        #expect(controller.currentTrackID == nil)
    }

    @Test func trackFadesInFromSilence() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        let target = PlayerSettings.defaultMusicVolume * BackgroundMusicController.musicMixScale
        controller.apply(.track("title_menu"))
        await waitFor { mock.playCount == 1 && mock.volume == target }
        #expect(mock.loadCalls == ["title_menu"])
        #expect(controller.currentTrackID == "title_menu")
        #expect(mock.fadeCalls.map(\.0) == [target])
        #expect(mock.fadeCalls.map(\.1) == [0.5])
    }

    @Test func sameTrackIsNoOp() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        controller.apply(.track("title_menu"))
        await waitFor { mock.playCount == 1 }
        controller.apply(.track("title_menu"))
        await Task.yield()
        #expect(mock.loadCalls == ["title_menu"])
        #expect(mock.playCount == 1)
    }

    @Test func trackChangeFadesOutThenIn() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        let target = PlayerSettings.defaultMusicVolume * BackgroundMusicController.musicMixScale
        controller.apply(.track("title_menu"))
        await waitFor { controller.currentTrackID == "title_menu" && mock.volume == target }

        controller.apply(.track("level"))
        await waitFor { controller.currentTrackID == "level" && mock.volume == target }

        #expect(mock.loadCalls == ["title_menu", "level"])
        #expect(mock.stopCount == 1)
        #expect(mock.fadeCalls.map(\.0) == [target, 0, target])
        #expect(mock.fadeCalls.map(\.1) == [0.5, 0.5, 0.5])
    }

    @Test func silenceFadesOutAndClears() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        controller.apply(.track("title_menu"))
        await waitFor { controller.currentTrackID == "title_menu" }

        controller.apply(.silence)
        await waitFor { controller.currentTrackID == nil && mock.stopCount == 1 }
        #expect(mock.fadeCalls.last?.0 == 0)
    }

    @Test func pauseAndResumeForBackground() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 0)
        controller.apply(.track("title_menu"))
        await waitFor { mock.isPlaying }

        controller.pauseForBackground()
        #expect(controller.isPausedForBackground)
        #expect(mock.pauseCount == 1)
        #expect(!mock.isPlaying)

        controller.resumeFromBackground()
        #expect(!controller.isPausedForBackground)
        #expect(mock.playCount == 2)
        #expect(mock.isPlaying)
    }

    @Test func fadeInUsesMusicVolume() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        controller.setMusicVolume(0.5)
        let target = 0.5 * BackgroundMusicController.musicMixScale
        controller.apply(.track("title_menu"))
        await waitFor { mock.playCount == 1 && mock.volume == target }
        #expect(mock.fadeCalls.map(\.0) == [target])
        #expect(controller.effectiveVolume == target)
    }

    @Test func disablingMutesWhileKeepingTrack() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 0)
        let target = PlayerSettings.defaultMusicVolume * BackgroundMusicController.musicMixScale
        controller.apply(.track("title_menu"))
        await waitFor { controller.currentTrackID == "title_menu" && mock.volume == target }

        controller.setMusicEnabled(false)
        #expect(controller.currentTrackID == "title_menu")
        #expect(mock.volume == 0)
        #expect(controller.effectiveVolume == 0)

        controller.setMusicEnabled(true)
        #expect(mock.volume == target)
        #expect(controller.effectiveVolume == target)
    }

    @Test func liveVolumeChangeUpdatesPlayer() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 0)
        let target = PlayerSettings.defaultMusicVolume * BackgroundMusicController.musicMixScale
        controller.apply(.track("title_menu"))
        await waitFor { mock.volume == target }

        controller.setMusicVolume(0.3)
        #expect(mock.volume == 0.3 * BackgroundMusicController.musicMixScale)
    }

    @Test func phoneticCueDuckLowersThenRestoresVolume() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 0)
        let base = PlayerSettings.defaultMusicVolume * BackgroundMusicController.musicMixScale
        controller.apply(.track("combat"))
        await waitFor { mock.volume == base }

        controller.duckForPhoneticCue(duration: 0.05)
        #expect(controller.isPhoneticDucked)
        #expect(mock.volume == base * SoundEffectsController.phoneticCueDuckScale)

        await waitFor(timeoutNanoseconds: 500_000_000) {
            !controller.isPhoneticDucked && mock.volume == base
        }
        #expect(!controller.isPhoneticDucked)
        #expect(mock.volume == base)
    }

    private func waitFor(
        timeoutNanoseconds: UInt64 = 200_000_000,
        _ condition: @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                break
            }
            await Task.yield()
        }
        #expect(condition())
    }
}
