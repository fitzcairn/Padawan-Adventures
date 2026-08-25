import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

struct VectorStrafeUseTests {
    @Test func itemIDMatchesCatalog() {
        #expect(VectorStrafeUse.itemID == "merchant-ware-vector")
    }

    @Test func visibleEnemiesRequireARevealedFloorAndTheCamera() {
        var world = TestWorldFactory.emptyFloor(width: 20, height: 20)
        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))
        let near = GameEntity(
            letter: "E",
            position: GridCoord(x: 3, y: 2, story: 0),
            enemyTypeID: "spider"
        )
        let far = GameEntity(
            letter: "E",
            position: GridCoord(x: 18, y: 18, story: 0),
            enemyTypeID: "spider"
        )
        let fogged = GameEntity(
            letter: "E",
            position: GridCoord(x: 4, y: 2, story: 0),
            enemyTypeID: "spider"
        )
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: [world.entities[0], near, far, fogged],
            spawn: world.spawn
        )

        let focus = IsometricMath.entityScreenPosition(GridCoord(x: 2, y: 2, story: 0))
        let shown: Set<GridCoord> = [near.position, far.position]
        let visible = VectorStrafeUse.visibleEnemies(
            in: world,
            shownFloorCells: shown,
            focus: focus,
            viewCenter: CGPoint(x: 400, y: 300),
            viewSize: CGSize(width: 240, height: 180),
            scale: 1
        )
        let ids = Set(visible.map(\.id))
        #expect(ids.contains(near.id))
        #expect(!ids.contains(far.id))
        #expect(!ids.contains(fogged.id))
    }

    @Test func flightPathFollowsIsometricSouthwest() {
        let config = IsometricConfig()
        let path = VectorStrafeUse.flightPath(
            through: .zero,
            viewSize: CGSize(width: 800, height: 500),
            config: config,
            scale: 1,
            offscreenPadding: 40
        )
        let dx = path.end.x - path.start.x
        let dy = path.end.y - path.start.y
        #expect(dx < 0)
        #expect(dy < 0)
        #expect(abs(dy / dx - config.tileHeight / config.tileWidth) < 0.001)
        #expect(path.start.x > 0 && path.start.y > 0)
        #expect(path.end.x < 0 && path.end.y < 0)
        #expect(path.start.y >= 250)
        #expect(path.end.y <= -250)
    }

    @Test func fireProgressProjectsOntoTheStrafe() {
        let start = CGPoint(x: 100, y: 80)
        let end = CGPoint(x: -100, y: -80)
        #expect(VectorStrafeUse.fireProgress(from: start, to: end, target: start) == 0.12)
        #expect(VectorStrafeUse.fireProgress(from: start, to: end, target: end) == 0.88)
        let mid = VectorStrafeUse.fireProgress(
            from: start,
            to: end,
            target: CGPoint(x: 0, y: 0)
        )
        #expect(abs(mid - 0.5) < 0.01)
    }
}
