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
        let floorZ = IsometricMath.effectiveFloorZ(for: coord, config: config)
        let entityZ = IsometricMath.effectiveEntityZ(for: coord, config: config)
        #expect(entityZ > floorZ)
    }

    @Test func entityAlwaysAboveAnyFloorTile() {
        let config = IsometricConfig()
        // Far sprite vs near floor — floor local depth is much higher, but bands separate them.
        let entity = GridCoord(x: 0, y: 0, story: 0)
        let frontFloor = GridCoord(x: 99, y: 99, story: 1)
        #expect(
            IsometricMath.effectiveEntityZ(for: entity, config: config)
                > IsometricMath.effectiveFloorZ(for: frontFloor, config: config)
        )
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

    @Test func fractionalGridFromEntityScreenRoundTrip() {
        let config = IsometricConfig()
        let screen = IsometricMath.entityScreenPosition(x: 3.25, y: 1.5, story: 0, config: config)
        let recovered = IsometricMath.fractionalGridFromEntityScreen(screen, story: 0, config: config)
        #expect(abs(recovered.x - 3.25) < 0.000_1)
        #expect(abs(recovered.y - 1.5) < 0.000_1)
    }

    @Test func deadzoneLeavesFocusWhenPlayerInside() {
        let config = IsometricConfig()
        let focus = IsometricMath.entityScreenPosition(x: 5, y: 5, story: 0, config: config)
        let player = IsometricMath.entityScreenPosition(x: 6.5, y: 4.5, story: 0, config: config)

        let next = IsometricMath.focusKeepingPlayerInDeadzone(
            focus: focus,
            player: player,
            story: 0,
            maxTiles: 2,
            config: config
        )
        #expect(abs(next.x - focus.x) < 0.000_1)
        #expect(abs(next.y - focus.y) < 0.000_1)
    }

    @Test func deadzoneShiftsFocusWhenPlayerExceedsPlusX() {
        let config = IsometricConfig()
        let focus = IsometricMath.entityScreenPosition(x: 5, y: 5, story: 0, config: config)
        let player = IsometricMath.entityScreenPosition(x: 8, y: 5, story: 0, config: config)

        let next = IsometricMath.focusKeepingPlayerInDeadzone(
            focus: focus,
            player: player,
            story: 0,
            maxTiles: 2,
            config: config
        )
        let nextGrid = IsometricMath.fractionalGridFromEntityScreen(next, story: 0, config: config)
        let playerGrid = IsometricMath.fractionalGridFromEntityScreen(player, story: 0, config: config)
        #expect(abs((playerGrid.x - nextGrid.x) - 2) < 0.000_1)
        #expect(abs(nextGrid.y - 5) < 0.000_1)
    }

    @Test func deadzoneClampsBothAxesIndependently() {
        let config = IsometricConfig()
        let focus = IsometricMath.entityScreenPosition(x: 5, y: 5, story: 0, config: config)
        let player = IsometricMath.entityScreenPosition(x: 8, y: 1, story: 0, config: config)

        let next = IsometricMath.focusKeepingPlayerInDeadzone(
            focus: focus,
            player: player,
            story: 0,
            maxTiles: 2,
            config: config
        )
        let nextGrid = IsometricMath.fractionalGridFromEntityScreen(next, story: 0, config: config)
        let playerGrid = IsometricMath.fractionalGridFromEntityScreen(player, story: 0, config: config)
        #expect(abs((playerGrid.x - nextGrid.x) - 2) < 0.000_1)
        #expect(abs((nextGrid.y - playerGrid.y) - 2) < 0.000_1)
    }

    @Test func containsFloorPointAtDiamondCenter() {
        let config = IsometricConfig()
        let coord = GridCoord(x: 3, y: 2, story: 0)
        let center = IsometricMath.entityScreenPosition(coord, config: config)
        #expect(IsometricTileGeometry.containsFloorPoint(center, at: coord, config: config))
    }

    @Test func containsFloorPointRejectsOutsideDiamond() {
        let config = IsometricConfig()
        let coord = GridCoord(x: 3, y: 2, story: 0)
        let origin = IsometricMath.gridToScreen(coord, config: config)
        let outside = CGPoint(x: origin.x + config.tileWidth, y: origin.y)
        #expect(!IsometricTileGeometry.containsFloorPoint(outside, at: coord, config: config))
    }

    @Test func pickVisibleFloorAtDiamondCenter() {
        let config = IsometricConfig()
        let world = TestWorldFactory.emptyFloor(width: 6, height: 6)
        let target = GridCoord(x: 3, y: 2, story: 0)
        let focus = IsometricMath.gridToScreen(GridCoord(x: 2, y: 2, story: 0), config: config)
        let viewCenter = CGPoint(x: 300, y: 200)
        let viewPoint = IsometricMath.viewPosition(
            worldPoint: IsometricMath.entityScreenPosition(target, config: config),
            focus: focus,
            viewCenter: viewCenter
        )

        let picked = IsometricMath.pickVisibleFloor(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: 0,
            in: world,
            config: config
        )
        #expect(picked == target)
    }

    @Test func pickVisibleFloorNearSharedEdgeChoosesFrontmost() {
        let config = IsometricConfig(tileWidth: 64, tileHeight: 32, wallHeight: 48)
        let world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let back = GridCoord(x: 0, y: 0, story: 0)
        let front = GridCoord(x: 1, y: 0, story: 0)
        // Midpoint of shared edge between (0,0) east–south and (1,0) west–north.
        let edgePoint = CGPoint(x: 16, y: -24)
        #expect(IsometricTileGeometry.containsFloorPoint(edgePoint, at: back, config: config))
        #expect(IsometricTileGeometry.containsFloorPoint(edgePoint, at: front, config: config))

        let focus = CGPoint.zero
        let viewCenter = CGPoint(x: 200, y: 200)
        let viewPoint = IsometricMath.viewPosition(
            worldPoint: edgePoint,
            focus: focus,
            viewCenter: viewCenter
        )

        let picked = IsometricMath.pickVisibleFloor(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: 0,
            in: world,
            config: config
        )
        #expect(picked == front)
        #expect(
            IsometricMath.floorSortValue(for: front, config: config)
                > IsometricMath.floorSortValue(for: back, config: config)
        )
    }

    @Test func pickVisibleFloorIgnoresWalls() {
        let config = IsometricConfig()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let floor = GridCoord(x: 1, y: 1, story: 0)
        let wall = GridCoord(x: 2, y: 2, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: wall)

        let focus = CGPoint.zero
        let viewCenter = CGPoint(x: 200, y: 200)
        let viewPoint = IsometricMath.viewPosition(
            worldPoint: IsometricMath.entityScreenPosition(floor, config: config),
            focus: focus,
            viewCenter: viewCenter
        )

        let picked = IsometricMath.pickVisibleFloor(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: 0,
            in: world,
            config: config
        )
        #expect(picked == floor)
    }

    @Test func pickTileReturnsWallCell() {
        let config = IsometricConfig()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let wall = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: wall)

        let focus = CGPoint.zero
        let viewCenter = CGPoint(x: 200, y: 200)
        let viewPoint = IsometricMath.viewPosition(
            worldPoint: IsometricMath.entityScreenPosition(wall, config: config),
            focus: focus,
            viewCenter: viewCenter
        )

        let picked = IsometricMath.pickTile(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: 0,
            in: world,
            config: config
        )
        #expect(picked == wall)
    }

    @Test func pickVisibleFloorReturnsNilForPit() {
        let config = IsometricConfig()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        // Surround with walls so only the pit diamond is under the tap.
        for y in 0..<3 {
            for x in 0..<3 where !(x == 1 && y == 1) {
                world.setTile(
                    Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
                    at: GridCoord(x: x, y: y, story: 0)
                )
            }
        }

        let focus = CGPoint.zero
        let viewCenter = CGPoint(x: 200, y: 200)
        let viewPoint = IsometricMath.viewPosition(
            worldPoint: IsometricMath.entityScreenPosition(pit, config: config),
            focus: focus,
            viewCenter: viewCenter
        )

        let pickedFloor = IsometricMath.pickVisibleFloor(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: 0,
            in: world,
            config: config
        )
        #expect(pickedFloor == nil)

        let pickedTile = IsometricMath.pickTile(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: 0,
            in: world,
            config: config
        )
        #expect(pickedTile == pit)
    }

    @Test func fitScaleShrinksLargeMapToView() {
        let config = IsometricConfig()
        let bounds = IsometricMath.mapScreenBounds(width: 40, height: 40, story: 0, config: config)
        let scale = IsometricMath.fitScale(mapBounds: bounds, viewSize: CGSize(width: 400, height: 300))
        #expect(scale <= 1)
        #expect(scale > 0)
        #expect(bounds.width * scale <= 400)
        #expect(bounds.height * scale <= 300)

        let center = IsometricMath.mapCenter(for: bounds)
        #expect(abs(center.x - bounds.midX) < 0.001)
        #expect(abs(center.y - bounds.midY) < 0.001)
    }

    @Test func worldPointFromViewAccountsForScale() {
        let focus = CGPoint(x: 10, y: 20)
        let viewCenter = CGPoint(x: 100, y: 100)
        let scale: CGFloat = 0.5
        let viewPoint = CGPoint(x: 130, y: 80)
        let world = IsometricMath.worldPointFromView(
            viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            scale: scale
        )
        #expect(abs(world.x - 70) < 0.001)
        #expect(abs(world.y - (-20)) < 0.001)
    }

    @Test func pickVisibleFloorReturnsNilWhenMiss() {
        let config = IsometricConfig()
        let world = TestWorldFactory.emptyFloor(width: 2, height: 2)
        let focus = CGPoint.zero
        let viewCenter = CGPoint(x: 200, y: 200)
        let viewPoint = IsometricMath.viewPosition(
            worldPoint: CGPoint(x: 500, y: 500),
            focus: focus,
            viewCenter: viewCenter
        )

        let picked = IsometricMath.pickVisibleFloor(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: 0,
            in: world,
            config: config
        )
        #expect(picked == nil)
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

    @Test func doorRendersFloorAndLadderWallIsPurple() {
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

        let doorFloor = door.children.first as? SKShapeNode
        #expect(doorFloor?.fillColor == PlaceholderFactory.floorColor)
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
        let slidePartner = GridCoord(x: 1, y: 0, story: 1)
        let slide = PlaceholderFactory.tileNode(
            for: Tile(kind: .slide(partner: slidePartner, lowerStory: 0)),
            at: GridCoord(x: 0, y: 0, story: 1),
            config: config
        )

        let rampSlope = ramp.children.first as? SKShapeNode
        let slideSlope = slide.children.first as? SKShapeNode
        #expect(rampSlope?.name == "connector-slope")
        #expect(slideSlope?.name == "connector-slope")
        #expect(rampSlope?.fillColor == PlaceholderFactory.rampColor)
        #expect(slideSlope?.fillColor == PlaceholderFactory.slideColor)
    }

    @Test func connectorSlopePathIsNonFlat() {
        let config = IsometricConfig(tileWidth: 40, tileHeight: 40, storyHeight: 40)
        let coord = GridCoord(x: 0, y: 0, story: 0)
        let partner = GridCoord(x: 1, y: 0, story: 0)
        let path = IsometricTileGeometry.connectorSlopePath(
            from: coord,
            partner: partner,
            config: config,
            rise: config.storyHeight
        )
        #expect(path != nil)
        let bounds = path!.boundingBox
        #expect(bounds.height > config.tileHeight)
    }

    @Test func rampPartnerCellDrawsNoSlope() {
        let config = IsometricConfig()
        let a = GridCoord(x: 0, y: 0, story: 0)
        let b = GridCoord(x: 1, y: 0, story: 0)
        let partnerNode = PlaceholderFactory.tileNode(
            for: Tile(kind: .ramp(partner: a, otherStory: 1)),
            at: b,
            config: config
        )
        #expect(partnerNode.children.isEmpty)
    }

    @Test func rampLandingFloorIsTinted() {
        let config = IsometricConfig()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .ramp(partner: b, otherStory: 1)), at: a)
        world.setTile(Tile(kind: .ramp(partner: a, otherStory: 1)), at: b)

        let landing = PlaceholderFactory.tileNode(
            for: Tile(kind: .floor(isPit: false)),
            at: a.onStory(1),
            in: world,
            config: config
        )
        #expect((landing.children.first as? SKShapeNode)?.fillColor == PlaceholderFactory.rampColor)
    }
}
