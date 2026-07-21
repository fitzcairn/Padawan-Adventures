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

    @Test func entitySortsAboveFloorAtSameCell() {
        let config = IsometricConfig()
        let coord = GridCoord(x: 3, y: 2, story: 0)
        let floorZ = IsometricMath.floorSortValue(for: coord, config: config)
        let entityZ = IsometricMath.entitySortValue(for: coord, config: config)
        #expect(entityZ > floorZ)
    }

    @Test func wallInFrontOccludesEntity() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 2, y: 2, story: 0)
        let wallInFront = GridCoord(x: 3, y: 2, story: 0)
        #expect(IsometricMath.wallOccludesEntity(wallCoord: wallInFront, entityCoord: entity, config: config))
    }

    @Test func wallBehindDoesNotOccludeEntity() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 3, y: 3, story: 0)
        let wallBehind = GridCoord(x: 2, y: 2, story: 0)
        #expect(!IsometricMath.wallOccludesEntity(wallCoord: wallBehind, entityCoord: entity, config: config))
    }

    @Test func entityDrawsAboveWallAtSameCell() {
        let config = IsometricConfig()
        let coord = GridCoord(x: 4, y: 1, story: 0)
        let wallZ = IsometricMath.wallSortValue(for: coord, config: config)
        let entityZ = IsometricMath.entitySortValue(for: coord, config: config)
        #expect(entityZ > wallZ)
    }

    @Test func upperStoryWallBehindDoesNotBuryLowerStoryEntity() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 8, y: 8, story: 0)
        let upperWallBehind = GridCoord(x: 1, y: 1, story: 1)
        #expect(!IsometricMath.wallOccludesEntity(wallCoord: upperWallBehind, entityCoord: entity, config: config))
    }

    @Test func upperStoryWallAtSameCellOccludesLowerEntity() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 4, y: 4, story: 0)
        let upperWall = GridCoord(x: 4, y: 4, story: 1)
        #expect(IsometricMath.wallOccludesEntity(wallCoord: upperWall, entityCoord: entity, config: config))
    }

    @Test func frontTilesRenderTowardBottomOfScreen() {
        let config = IsometricConfig()
        let near = IsometricMath.gridToScreen(GridCoord(x: 4, y: 4, story: 0), config: config)
        let far = IsometricMath.gridToScreen(GridCoord(x: 0, y: 0, story: 0), config: config)
        #expect(near.y < far.y)
    }

    @Test func focusStaysAtViewCenter() {
        let config = IsometricConfig()
        let focusCoord = GridCoord(x: 3, y: 5, story: 0)
        let focus = IsometricMath.gridToScreen(focusCoord, config: config)
        let viewCenter = CGPoint(x: 400, y: 300)

        let viewPos = IsometricMath.viewPosition(
            for: focusCoord,
            focus: focus,
            viewCenter: viewCenter,
            config: config
        )

        #expect(abs(viewPos.x - viewCenter.x) < 0.001)
        #expect(abs(viewPos.y - viewCenter.y) < 0.001)
    }

    @Test func worldMovesOppositeFocus() {
        let config = IsometricConfig()
        let viewCenter = CGPoint(x: 200, y: 200)
        let focusA = IsometricMath.gridToScreen(GridCoord(x: 1, y: 1, story: 0), config: config)
        let focusB = IsometricMath.gridToScreen(GridCoord(x: 2, y: 1, story: 0), config: config)
        let tile = GridCoord(x: 4, y: 4, story: 0)

        let offsetA = IsometricMath.worldRootOffset(focus: focusA, viewCenter: viewCenter)
        let offsetB = IsometricMath.worldRootOffset(focus: focusB, viewCenter: viewCenter)
        #expect(offsetB.x != offsetA.x || offsetB.y != offsetA.y)

        let tileViewA = IsometricMath.viewPosition(for: tile, focus: focusA, viewCenter: viewCenter, config: config)
        let tileViewB = IsometricMath.viewPosition(for: tile, focus: focusB, viewCenter: viewCenter, config: config)
        #expect(tileViewA.x != tileViewB.x || tileViewA.y != tileViewB.y)
    }

    @Test func gridFromViewRoundTrip() {
        let config = IsometricConfig()
        let focusCoord = GridCoord(x: 2, y: 2, story: 0)
        let focus = IsometricMath.gridToScreen(focusCoord, config: config)
        let viewCenter = CGPoint(x: 300, y: 200)
        let target = GridCoord(x: 5, y: 3, story: 0)

        let viewPoint = IsometricMath.viewPosition(
            for: target,
            focus: focus,
            viewCenter: viewCenter,
            config: config
        )
        let recovered = IsometricMath.gridFromView(
            viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: target.story,
            config: config
        )

        #expect(recovered == target)
    }

    @Test func panMovesFocusOppositeDrag() {
        let focus = CGPoint(x: 100, y: 50)
        let drag = CGPoint(x: 20, y: -10)
        let next = IsometricMath.focusAfterPan(currentFocus: focus, dragDelta: drag)

        #expect(next.x == 80)
        #expect(next.y == 60)
    }
}

struct ViewportGestureTrackerTests {
    @Test func shortTouchIsTap() {
        var tracker = ViewportGestureTracker()
        tracker.begin(at: .zero)
        _ = tracker.move(to: CGPoint(x: 5, y: 0))
        let wasTap = tracker.end()
        #expect(wasTap)
    }

    @Test func longDragIsPan() {
        var tracker = ViewportGestureTracker()
        tracker.begin(at: .zero)
        let delta = tracker.move(to: CGPoint(x: ViewportGestureTracker.panThreshold + 1, y: 0))
        #expect(delta != nil)
        #expect(tracker.isPanning)
        let wasTap = tracker.end()
        #expect(!wasTap)
    }

    @Test func panReportsIncrementalDeltas() {
        var tracker = ViewportGestureTracker()
        tracker.begin(at: .zero)
        _ = tracker.move(to: CGPoint(x: 20, y: 0))
        let second = tracker.move(to: CGPoint(x: 30, y: 5))
        #expect(second?.x == 10)
        #expect(second?.y == 5)
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
        let wallBounds = wall.calculateAccumulatedFrame()

        #expect(wallBounds.height > floorBounds.height)
    }

    @Test func leftWallFaceSlantsAlongWestSouthEdge() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let path = IsometricTileGeometry.leftWallFacePath(config: config)
        let bounds = path.boundingBox

        #expect(bounds.minX < 0)
        #expect(bounds.maxX <= 0.001)
        #expect(bounds.height > config.tileHeight)
    }

    @Test func rightWallFaceSlantsAlongEastSouthEdge() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let path = IsometricTileGeometry.rightWallFacePath(config: config)
        let bounds = path.boundingBox

        #expect(bounds.maxX > 0)
        #expect(bounds.minX >= -0.001)
        #expect(bounds.height > config.tileHeight)
    }

    @Test func wallFacesAreNotAxisAlignedRectangles() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let left = IsometricTileGeometry.leftWallFacePath(config: config).boundingBox
        let right = IsometricTileGeometry.rightWallFacePath(config: config).boundingBox

        // Perspective faces are parallelograms: width is half-tile, not full tileWidth.
        #expect(left.width < config.tileWidth)
        #expect(right.width < config.tileWidth)
        #expect(abs(left.width - config.tileWidth / 2) < 0.001)
        #expect(abs(right.width - config.tileWidth / 2) < 0.001)
    }

    @Test func opaqueNeighborCullsSharedWallFace() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let east = GridCoord(x: 2, y: 1, story: 0)
        let south = GridCoord(x: 1, y: 2, story: 0)

        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: a)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: east)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: south)

        let faces = IsometricTileGeometry.visibleFaces(at: a, in: world)
        #expect(!faces.contains(.right))
        #expect(!faces.contains(.left))
        #expect(faces.contains(.top))
    }

    @Test func openNeighborKeepsPerspectiveFace() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: a)

        let faces = IsometricTileGeometry.visibleFaces(at: a, in: world)
        #expect(faces.contains(.left))
        #expect(faces.contains(.right))
    }

    @Test func floorIsWhiteAndPitIsTransparent() {
        let config = IsometricConfig()
        let floor = PlaceholderFactory.tileNode(
            for: Tile(kind: .floor(isPit: false)),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )
        let pit = PlaceholderFactory.tileNode(
            for: Tile(kind: .floor(isPit: true)),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )

        let floorShape = floor.children.first as? SKShapeNode
        #expect(floorShape?.fillColor == PlaceholderFactory.floorColor)
        #expect(pit.children.isEmpty)
    }

    @Test func doorIsTransparentAndLadderWallIsPurple() {
        let config = IsometricConfig()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let doorCoord = GridCoord(x: 1, y: 1, story: 0)
        let ladderCoord = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true, hasLadder: false)), at: doorCoord)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: ladderCoord)

        let door = PlaceholderFactory.tileNode(
            for: world.tile(at: doorCoord)!,
            at: doorCoord,
            in: world,
            config: config
        )
        let ladder = PlaceholderFactory.tileNode(
            for: world.tile(at: ladderCoord)!,
            at: ladderCoord,
            in: world,
            config: config
        )

        #expect(door.children.isEmpty)
        #expect(!ladder.children.isEmpty)
    }

    @Test func rampIsRedAndSlideIsBlue() {
        let config = IsometricConfig()
        let partner = GridCoord(x: 1, y: 0, story: 0)
        let ramp = PlaceholderFactory.tileNode(
            for: Tile(kind: .ramp(partner: partner, otherStory: 1)),
            at: GridCoord(x: 0, y: 0, story: 0),
            config: config
        )
        let slide = PlaceholderFactory.tileNode(
            for: Tile(kind: .slide(partner: partner, lowerStory: 0)),
            at: GridCoord(x: 0, y: 0, story: 1),
            config: config
        )

        #expect((ramp.children.first as? SKShapeNode)?.fillColor == PlaceholderFactory.rampColor)
        #expect((slide.children.first as? SKShapeNode)?.fillColor == PlaceholderFactory.slideColor)
    }
}
