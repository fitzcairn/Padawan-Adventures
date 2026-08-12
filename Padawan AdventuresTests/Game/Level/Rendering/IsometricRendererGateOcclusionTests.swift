import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct IsometricRendererGateOcclusionTests {
    /// Wall column at x = 5 with a 2-cell gate at y = 4...5, rooms east and west.
    private static let back = GridCoord(x: 5, y: 4, story: 0)
    private static let front = GridCoord(x: 5, y: 5, story: 0)

    private func gatedWorld() -> GameWorld {
        var world = TestWorldFactory.emptyFloor(width: 9, height: 9)
        for y in 0..<9 {
            world.setTile(Tile(kind: .wall), at: GridCoord(x: 5, y: y, story: 0))
        }
        for cell in [Self.back, Self.front] {
            world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: cell)
        }
        return world
    }

    /// `openGate` turns the strip into floor while the detached sprite spends the whole
    /// dissolve on screen, so the renderer has to remember the strip. Without it the
    /// player standing in the doorway he just opened is painted over by the fading gate.
    @Test func dissolvingGateStillSortsAgainstEntities() {
        var world = gatedWorld()
        let renderer = IsometricRenderer()

        _ = renderer.detachGateNode(at: Self.back, in: world)
        _ = world.openGate(at: Self.back)

        #expect(PlaceholderFactory.gateOccluders(in: world, story: 0).isEmpty)
        #expect(renderer.entityGateOccluders.map(\.sortCoord) == [Self.front])

        let gateZ = IsometricMath.wallSortValue(for: Self.front, config: renderer.config)
        let playerZ = PlaceholderFactory.entitySortValueAccountingForGates(
            x: Double(Self.back.x),
            y: Double(Self.back.y),
            story: Self.back.story,
            gates: renderer.entityGateOccluders,
            config: renderer.config
        )
        #expect(playerZ > gateZ)
    }

    @Test func attachClearsDissolvingStrips() {
        let world = gatedWorld()
        let renderer = IsometricRenderer()
        _ = renderer.detachGateNode(at: Self.back, in: world)
        #expect(!renderer.dissolvingGateOccluders.isEmpty)

        renderer.attach(to: SKScene(size: CGSize(width: 320, height: 480)))
        #expect(renderer.dissolvingGateOccluders.isEmpty)
    }
}
