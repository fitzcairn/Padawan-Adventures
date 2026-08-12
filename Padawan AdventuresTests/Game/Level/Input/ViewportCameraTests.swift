import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct ViewportCameraTests {
    @Test func startsFollowingPlayer() {
        var camera = ViewportCamera()
        #expect(camera.followsPlayer)
        #expect(camera.advance(deltaTime: 0.1, playerFocus: .zero) == nil)
    }

    @Test func panParksViewportUntilDestinationTap() {
        var camera = ViewportCamera()
        camera.noteUserPan()
        #expect(!camera.followsPlayer)
        #expect(camera.advance(deltaTime: 0.1, playerFocus: CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func destinationTapWhileFollowingDoesNotRecenter() {
        var camera = ViewportCamera()
        camera.noteDestinationChosen(from: CGPoint(x: 40, y: -20))
        #expect(camera.followsPlayer)
        #expect(camera.advance(deltaTime: 0.1, playerFocus: .zero) == nil)
    }

    @Test func destinationTapAfterPanGlidesToPlayerThenFollows() {
        var camera = ViewportCamera()
        camera.noteUserPan()
        let start = CGPoint(x: 80, y: -40)
        let player = CGPoint(x: 10, y: 20)
        camera.noteDestinationChosen(from: start)

        let mid = camera.advance(deltaTime: ViewportCamera.recenterDuration / 2, playerFocus: player)
        let expectedMid = IsometricMath.interpolatedFocus(
            from: start,
            to: player,
            progress: 0.5
        )
        #expect(mid?.x == expectedMid.x)
        #expect(mid?.y == expectedMid.y)
        #expect(!camera.followsPlayer)

        let end = camera.advance(deltaTime: ViewportCamera.recenterDuration, playerFocus: player)
        #expect(end?.x == player.x)
        #expect(end?.y == player.y)
        #expect(camera.followsPlayer)
        #expect(camera.advance(deltaTime: 0.1, playerFocus: player) == nil)
    }

    @Test func recenterTracksAMovingPlayer() {
        var camera = ViewportCamera()
        camera.noteUserPan()
        camera.noteDestinationChosen(from: .zero)

        let first = CGPoint(x: 20, y: 0)
        _ = camera.advance(deltaTime: ViewportCamera.recenterDuration / 2, playerFocus: first)

        let second = CGPoint(x: 40, y: 10)
        let end = camera.advance(deltaTime: ViewportCamera.recenterDuration, playerFocus: second)
        #expect(end?.x == second.x)
        #expect(end?.y == second.y)
    }

    @Test func panDuringRecenterParksAgain() {
        var camera = ViewportCamera()
        camera.noteUserPan()
        camera.noteDestinationChosen(from: .zero)
        _ = camera.advance(deltaTime: 0.1, playerFocus: CGPoint(x: 50, y: 50))
        camera.noteUserPan()
        #expect(!camera.followsPlayer)
        #expect(camera.advance(deltaTime: 0.1, playerFocus: CGPoint(x: 50, y: 50)) == nil)
    }

    @Test func snapToFollowingCancelsAParkedOrGlidingCamera() {
        var camera = ViewportCamera()
        camera.noteUserPan()
        camera.snapToFollowing()
        #expect(camera.followsPlayer)

        camera.noteUserPan()
        camera.noteDestinationChosen(from: .zero)
        camera.snapToFollowing()
        #expect(camera.followsPlayer)
        #expect(camera.advance(deltaTime: 0.1, playerFocus: .zero) == nil)
    }
}
