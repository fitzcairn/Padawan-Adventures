import CoreGraphics
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

    @Test func higherGridYFloorDrawsOverLowerGridYWall() {
        let config = IsometricConfig()
        let wallBack = GridCoord(x: 0, y: 100, story: 0)
        let floorMid = GridCoord(x: 0, y: 200, story: 0)
        let wallFront = GridCoord(x: 0, y: 300, story: 0)

        #expect(
            IsometricMath.effectiveFloorZ(for: floorMid, config: config)
                > IsometricMath.floorBandBase + IsometricMath.wallSortValue(for: wallBack, config: config)
        )
        #expect(
            IsometricMath.floorBandBase + IsometricMath.wallSortValue(for: wallFront, config: config)
                > IsometricMath.effectiveFloorZ(for: floorMid, config: config)
        )
    }

    @Test func frontFloorDrawsOverBackEntity() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 0, y: 100, story: 0)
        let frontFloor = GridCoord(x: 0, y: 200, story: 0)
        #expect(
            IsometricMath.effectiveFloorZ(for: frontFloor, config: config)
                > IsometricMath.effectiveEntityZ(for: entity, config: config)
        )
    }

    @Test func higherGridYWallDrawsOverLowerGridYEntity() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 0, y: 100, story: 0)
        let wallFront = GridCoord(x: 0, y: 300, story: 0)
        #expect(IsometricMath.wallOccludesEntity(wallCoord: wallFront, entityCoord: entity, config: config))
    }

    @Test func higherGridYDrawsOverLowerGridYAmongWalls() {
        let config = IsometricConfig()
        let back = GridCoord(x: 0, y: 100, story: 0)
        let front = GridCoord(x: 0, y: 300, story: 0)
        #expect(
            IsometricMath.wallSortValue(for: front, config: config)
                > IsometricMath.wallSortValue(for: back, config: config)
        )
    }

    @Test func wallInFrontOccludesEntity() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 2, y: 2, story: 0)
        let wallInFront = GridCoord(x: 3, y: 2, story: 0)
        #expect(IsometricMath.wallOccludesEntity(wallCoord: wallInFront, entityCoord: entity, config: config))
    }

    /// With `ignoresSiblingOrder`, SpriteKit sorts by accumulated z. Nested face/body
    /// biases must not let a sprite leap over a front wall's side faces.
    @Test func frontWallSideFaceAccumulatedZBeatsEntitySprite() {
        let config = IsometricConfig()
        let entity = GridCoord(x: 2, y: 2, story: 0)
        let wallInFront = GridCoord(x: 3, y: 2, story: 0)

        let entitySpriteZ = IsometricMath.entitySortValue(for: entity, config: config)
            + PlaceholderFactory.entityLabelZ
        let wallLeftFaceZ = IsometricMath.wallSortValue(for: wallInFront, config: config)
            + PlaceholderFactory.wallFaceLeftZ

        #expect(wallLeftFaceZ > entitySpriteZ)
    }

    @Test func entitySpriteAccumulatedZBeatsSameCellWallTop() {
        let config = IsometricConfig()
        let coord = GridCoord(x: 4, y: 1, story: 0)

        let entityBodyZ = IsometricMath.entitySortValue(for: coord, config: config)
            + PlaceholderFactory.entityBodyZ
        let wallTopZ = IsometricMath.wallSortValue(for: coord, config: config)
            + PlaceholderFactory.wallFaceTopZ

        #expect(entityBodyZ > wallTopZ)
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
        world.setTile(Tile(kind: .wall(destructible: false)), at: wall)

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
        world.setTile(Tile(kind: .wall(destructible: false)), at: wall)

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

    @Test func pickVisibleFloorReturnsDrawnPit() {
        let config = IsometricConfig()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        // Surround with walls so only the pit diamond is under the tap.
        for y in 0..<3 {
            for x in 0..<3 where !(x == 1 && y == 1) {
                world.setTile(
                    Tile(kind: .wall(destructible: false)),
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
        #expect(pickedFloor == pit)

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
