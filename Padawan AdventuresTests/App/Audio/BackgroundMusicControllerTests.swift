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
        controller.apply(.track("menu_theme"))
        await waitFor { mock.playCount == 1 && mock.volume == 1 }
        #expect(mock.loadCalls == ["menu_theme"])
        #expect(controller.currentTrackID == "menu_theme")
        #expect(mock.fadeCalls.map(\.0) == [1])
        #expect(mock.fadeCalls.map(\.1) == [0.5])
    }

    @Test func sameTrackIsNoOp() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        controller.apply(.track("menu_theme"))
        await waitFor { mock.playCount == 1 }
        controller.apply(.track("menu_theme"))
        await Task.yield()
        #expect(mock.loadCalls == ["menu_theme"])
        #expect(mock.playCount == 1)
    }

    @Test func trackChangeFadesOutThenIn() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        controller.apply(.track("menu_theme"))
        await waitFor { controller.currentTrackID == "menu_theme" && mock.volume == 1 }

        controller.apply(.track("level_theme"))
        await waitFor { controller.currentTrackID == "level_theme" && mock.volume == 1 }

        #expect(mock.loadCalls == ["menu_theme", "level_theme"])
        #expect(mock.stopCount == 1)
        #expect(mock.fadeCalls.map(\.0) == [1, 0, 1])
        #expect(mock.fadeCalls.map(\.1) == [0.5, 0.5, 0.5])
    }

    @Test func silenceFadesOutAndClears() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 1)
        controller.apply(.track("menu_theme"))
        await waitFor { controller.currentTrackID == "menu_theme" }

        controller.apply(.silence)
        await waitFor { controller.currentTrackID == nil && mock.stopCount == 1 }
        #expect(mock.fadeCalls.last?.0 == 0)
    }

    @Test func pauseAndResumeForBackground() async {
        let mock = MockMusicAudioPlayer()
        let controller = BackgroundMusicController(player: mock)
        controller.configure(fadeSeconds: 0)
        controller.apply(.track("menu_theme"))
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
