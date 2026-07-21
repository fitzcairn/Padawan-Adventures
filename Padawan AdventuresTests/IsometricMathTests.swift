import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

struct IsometricMathTests {
    @Test func roundTripGridScreen() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, storyHeight: 48)
        let coord = GridCoord(x: 5, y: 3, story: 1)

        let screen = IsometricMath.gridToScreen(coord, config: config)
        let recovered = IsometricMath.screenToGrid(screen, story: coord.story, config: config)

        #expect(recovered.x == coord.x)
        #expect(recovered.y == coord.y)
        #expect(recovered.story == coord.story)
    }

    @Test func depthSortOrdersUpperStoryAboveLower() {
        let config = IsometricConfig()
        let lower = IsometricMath.depthSortValue(for: GridCoord(x: 4, y: 4, story: 0), config: config)
        let upper = IsometricMath.depthSortValue(for: GridCoord(x: 4, y: 4, story: 1), config: config)
        #expect(upper > lower)
    }

    @Test func frontTilesRenderTowardBottomOfScreen() {
        let config = IsometricConfig()
        let near = IsometricMath.gridToScreen(GridCoord(x: 4, y: 4, story: 0), config: config)
        let far = IsometricMath.gridToScreen(GridCoord(x: 0, y: 0, story: 0), config: config)
        #expect(near.y < far.y)
    }

    @Test func anchorStaysAtViewCenter() {
        let config = IsometricConfig()
        let anchor = GridCoord(x: 3, y: 5, story: 0)
        let viewCenter = CGPoint(x: 400, y: 300)

        let viewPos = IsometricMath.viewPosition(
            for: anchor,
            anchor: anchor,
            viewCenter: viewCenter,
            config: config
        )

        #expect(abs(viewPos.x - viewCenter.x) < 0.001)
        #expect(abs(viewPos.y - viewCenter.y) < 0.001)
    }

    @Test func worldMovesOppositeAnchor() {
        let config = IsometricConfig()
        let viewCenter = CGPoint(x: 200, y: 200)
        let anchorA = GridCoord(x: 1, y: 1, story: 0)
        let anchorB = GridCoord(x: 2, y: 1, story: 0)
        let tile = GridCoord(x: 4, y: 4, story: 0)

        let offsetA = IsometricMath.worldRootOffset(anchor: anchorA, viewCenter: viewCenter, config: config)
        let offsetB = IsometricMath.worldRootOffset(anchor: anchorB, viewCenter: viewCenter, config: config)
        #expect(offsetB.x != offsetA.x || offsetB.y != offsetA.y)

        let tileViewA = IsometricMath.viewPosition(for: tile, anchor: anchorA, viewCenter: viewCenter, config: config)
        let tileViewB = IsometricMath.viewPosition(for: tile, anchor: anchorB, viewCenter: viewCenter, config: config)
        #expect(tileViewA.x != tileViewB.x || tileViewA.y != tileViewB.y)
    }

    @Test func gridFromViewRoundTrip() {
        let config = IsometricConfig()
        let anchor = GridCoord(x: 2, y: 2, story: 0)
        let viewCenter = CGPoint(x: 300, y: 200)
        let target = GridCoord(x: 5, y: 3, story: 0)

        let viewPoint = IsometricMath.viewPosition(
            for: target,
            anchor: anchor,
            viewCenter: viewCenter,
            config: config
        )
        let recovered = IsometricMath.gridFromView(
            viewPoint,
            anchor: anchor,
            viewCenter: viewCenter,
            story: target.story,
            config: config
        )

        #expect(recovered == target)
    }
}

struct PlaceholderFactoryTests {
    @Test func floorTileUsesHorizontalEdges() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let floor = PlaceholderFactory.horizontalFloorNode(isPit: false, config: config)
        let bounds = floor.path?.boundingBox ?? .zero

        #expect(bounds.width > 0)
        #expect(bounds.height > 0)
        #expect(abs(bounds.maxY - bounds.minY) > abs(bounds.maxX - bounds.minX) * 0.1)
    }

    @Test func wallTileIsTallerThanFloor() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let floor = PlaceholderFactory.horizontalFloorNode(isPit: false, config: config)
        let wall = PlaceholderFactory.verticalWallNode(destructible: false, config: config)
        let floorBounds = floor.path?.boundingBox ?? .zero
        let wallBounds = wall.path?.boundingBox ?? .zero

        #expect(wallBounds.height > floorBounds.height)
    }
}
