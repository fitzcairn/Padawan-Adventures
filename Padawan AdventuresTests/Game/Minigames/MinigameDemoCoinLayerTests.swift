import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct MinigameDemoCoinLayerTests {
    @Test func arcPointEndpointsAndApex() {
        let start = CGPoint(x: 100, y: 50)
        let end = CGPoint.zero
        let control = CGPoint(x: 25, y: 200)

        let atStart = MinigameDemoCoinLayer.arcPoint(t: 0, start: start, control: control, end: end)
        #expect(atStart == start)

        let atEnd = MinigameDemoCoinLayer.arcPoint(t: 1, start: start, control: control, end: end)
        #expect(atEnd == end)

        let mid = MinigameDemoCoinLayer.arcPoint(t: 0.5, start: start, control: control, end: end)
        #expect(mid.y > start.y)
        #expect(mid.y > end.y)
    }

    @Test func flyCoinToCornerRemovesNodeAndCountsFlight() async {
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let coins = MinigameDemoCoinLayer(scene: scene)

        #expect(scene.childNode(withName: MinigameDemoCoinLayer.rootName) != nil)

        await coins.flyCoinToCorner(
            from: CGPoint(x: 100, y: 100),
            holdSeconds: 0.01,
            flightSeconds: 0.01
        )

        #expect(coins.flightCount == 1)
        #expect(scene.childNode(withName: MinigameDemoCoinLayer.rootName)?.children.isEmpty == true)
    }

    @Test func flyToCornerClearsDroppedCoins() async {
        let scene = SKScene(size: CGSize(width: 400, height: 800))
        let layer = MinigameDemoCoinLayer(scene: scene)
        layer.dropCoin(at: CGPoint(x: 100, y: 200))
        layer.dropCoin(at: CGPoint(x: 200, y: 300))
        #expect(layer.count == 2)

        await layer.flyToCorner(holdSeconds: 0.01, flightSeconds: 0.01)
        #expect(layer.count == 0)
    }

    @Test func flyToCornerOnEmptyLayerIsANoOp() async {
        let scene = SKScene(size: CGSize(width: 400, height: 800))
        let layer = MinigameDemoCoinLayer(scene: scene)
        await layer.flyToCorner(holdSeconds: 0.01, flightSeconds: 0.01)
        #expect(layer.count == 0)
    }
}
