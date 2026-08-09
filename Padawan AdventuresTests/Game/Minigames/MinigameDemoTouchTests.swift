import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct MinigameDemoTouchTests {
    @Test func locationInSKViewRoundTripsThroughSceneConversion() {
        let sceneSize = CGSize(width: 390, height: 844)
        let scene = SKScene(size: sceneSize)
        scene.scaleMode = .aspectFit
        scene.anchorPoint = .zero

        let view = SKView(frame: CGRect(origin: .zero, size: sceneSize))
        view.presentScene(scene)

        let scenePoint = CGPoint(x: 120, y: 80)
        let touch = MinigameDemoTouch(point: scenePoint)

        let viewPoint = touch.location(in: view)
        let expectedView = scene.convertPoint(toView: scenePoint)
        #expect(abs(viewPoint.x - expectedView.x) < 0.5)
        #expect(abs(viewPoint.y - expectedView.y) < 0.5)

        // SpriteKit's node API converts view → scene; with the fix this lands back
        // on the original scene point (not a Y-flipped miss).
        let roundTrip = touch.location(in: scene)
        #expect(abs(roundTrip.x - scenePoint.x) < 0.5)
        #expect(abs(roundTrip.y - scenePoint.y) < 0.5)
    }

    @Test func locationWithoutViewPassesScenePointThrough() {
        let scenePoint = CGPoint(x: 50, y: 60)
        let touch = MinigameDemoTouch(point: scenePoint)
        #expect(touch.location(in: nil) == scenePoint)
    }
}
