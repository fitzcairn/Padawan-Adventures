import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct MovementSystemTests {
    @Test func pathDurationMatchesSpeed() {
        var movement = MovementSystem(tilesPerSecond: 1.0)
        let path = [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 1, y: 0, story: 0),
            GridCoord(x: 2, y: 0, story: 0),
        ]

        let duration = movement.totalDuration(for: path)
        #expect(duration == 2.0)
    }

    @Test func diagonalSegmentUsesEuclideanDuration() {
        var movement = MovementSystem(tilesPerSecond: 1.0)
        let path = [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 1, y: 1, story: 0),
        ]
        let duration = movement.totalDuration(for: path)
        #expect(abs(duration - 2.0.squareRoot()) < 0.000_001)
    }

    @Test func speedCanBeChangedAtRuntime() {
        var movement = MovementSystem(tilesPerSecond: 1.0)
        let path = [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 1, y: 0, story: 0),
        ]
        #expect(movement.totalDuration(for: path) == 1.0)

        movement.tilesPerSecond = 2.0
        #expect(movement.totalDuration(for: path) == 0.5)
    }

    @Test func movementReachesDestination() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        var movement = MovementSystem()
        let path = [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 1, y: 0, story: 0),
        ]
        movement.begin(path: path)

        _ = movement.update(deltaTime: 10, world: &world)
        #expect(world.playerPosition == GridCoord(x: 1, y: 0, story: 0))
        #expect(movement.isMoving == false)
    }

    @Test func occupancyFlipsAtTileBorder() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let start = GridCoord(x: 0, y: 0, story: 0)
        let end = GridCoord(x: 1, y: 0, story: 0)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, end])

        // Just under half a tile at 1 tile/s → 0.5s per half segment.
        _ = movement.update(deltaTime: 0.49, world: &world)
        #expect(world.playerPosition == start)
        #expect(movement.segmentProgress < 0.5)

        _ = movement.update(deltaTime: 0.02, world: &world)
        #expect(world.playerPosition == end)
        #expect(movement.segmentProgress >= 0.5)
        #expect(movement.isMoving == true)
    }

    @Test func displayPositionMovesContinuously() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let start = GridCoord(x: 0, y: 0, story: 0)
        let end = GridCoord(x: 1, y: 0, story: 0)
        world.setPlayerPosition(start)

        var movement = MovementSystem()
        movement.begin(path: [start, end])

        let before = movement.interpolatedScreenPosition(in: world)
        _ = movement.update(deltaTime: SimulationClock.tickDuration, world: &world)
        let after = movement.interpolatedScreenPosition(in: world)

        #expect(after != before)
        #expect(movement.segmentProgress > 0)
        #expect(movement.segmentProgress < 1)
    }

    @Test func repathPreservesScreenPosition() {
        var world = TestWorldFactory.emptyFloor(width: 6, height: 4)
        let start = GridCoord(x: 0, y: 0, story: 0)
        world.setPlayerPosition(start)

        var movement = MovementSystem()
        movement.begin(path: [
            start,
            GridCoord(x: 1, y: 0, story: 0),
            GridCoord(x: 2, y: 0, story: 0),
        ])

        _ = movement.update(deltaTime: 0.3, world: &world)
        let before = movement.interpolatedScreenPosition(in: world)
        let beforePose = movement.fractionalPosition()

        movement.begin(path: [
            start,
            GridCoord(x: 0, y: 1, story: 0),
            GridCoord(x: 0, y: 2, story: 0),
        ])

        let after = movement.interpolatedScreenPosition(in: world)
        let afterPose = movement.fractionalPosition()
        #expect(after == before)
        #expect(abs(afterPose.x - beforePose.x) < 0.000_001)
        #expect(abs(afterPose.y - beforePose.y) < 0.000_001)
    }

    @Test func repathMovesTowardNewWaypointNotBackToStartCenter() {
        var world = TestWorldFactory.emptyFloor(width: 6, height: 4)
        let start = GridCoord(x: 0, y: 0, story: 0)
        let newWaypoint = GridCoord(x: 0, y: 1, story: 0)
        world.setPlayerPosition(start)

        var movement = MovementSystem()
        movement.begin(path: [
            start,
            GridCoord(x: 1, y: 0, story: 0),
            GridCoord(x: 2, y: 0, story: 0),
        ])

        _ = movement.update(deltaTime: 0.3, world: &world)
        let atRepath = movement.interpolatedScreenPosition(in: world)
        let startCenter = IsometricMath.entityScreenPosition(start)

        movement.begin(path: [start, newWaypoint, GridCoord(x: 0, y: 2, story: 0)])
        _ = movement.update(deltaTime: SimulationClock.tickDuration, world: &world)
        let afterTick = movement.interpolatedScreenPosition(in: world)
        let waypointCenter = IsometricMath.entityScreenPosition(newWaypoint)

        // Moved away from the frozen repath pose toward the new waypoint.
        #expect(afterTick != atRepath)
        let distBefore = screenDistance(atRepath, waypointCenter)
        let distAfter = screenDistance(afterTick, waypointCenter)
        #expect(distAfter < distBefore)

        // Did not snap back to the occupancy tile center.
        #expect(screenDistance(afterTick, startCenter) > 0.1)
    }

    @Test func retargetKeepsProgressWhenNextWaypointUnchanged() {
        var world = TestWorldFactory.emptyFloor(width: 8, height: 4)
        let start = GridCoord(x: 0, y: 0, story: 0)
        let next = GridCoord(x: 1, y: 0, story: 0)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, next, GridCoord(x: 2, y: 0, story: 0)])
        _ = movement.update(deltaTime: 0.3, world: &world)

        let progressBefore = movement.segmentProgress
        let poseBefore = movement.fractionalPosition()
        let screenBefore = movement.interpolatedScreenPosition(in: world)

        // Same next waypoint, longer / redirected suffix.
        movement.retarget(path: [
            start,
            next,
            GridCoord(x: 1, y: 1, story: 0),
            GridCoord(x: 1, y: 2, story: 0),
        ])

        #expect(movement.segmentEnd == next)
        #expect(abs(movement.segmentProgress - progressBefore) < 0.000_001)
        #expect(abs(movement.fractionalPosition().x - poseBefore.x) < 0.000_001)
        #expect(abs(movement.fractionalPosition().y - poseBefore.y) < 0.000_001)
        #expect(movement.interpolatedScreenPosition(in: world) == screenBefore)
    }

    @Test func finishCurrentSegmentAndStopDoesNotSnapPose() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let start = GridCoord(x: 0, y: 0, story: 0)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [
            start,
            GridCoord(x: 1, y: 0, story: 0),
            GridCoord(x: 2, y: 0, story: 0),
        ])
        _ = movement.update(deltaTime: 0.3, world: &world)
        let before = movement.interpolatedScreenPosition(in: world)

        movement.finishCurrentSegmentAndStop()
        #expect(movement.isMoving)
        #expect(movement.path.count == 2)
        #expect(movement.interpolatedScreenPosition(in: world) == before)
    }

    @Test func enteringGateEmitsApproachTileAndStopsMovement() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 0, y: 1, story: 0)
        let gate = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: gate)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, gate])

        let events = movement.update(deltaTime: 10, world: &world)
        #expect(events.contains(.gate(gate: gate, approach: start)))
        #expect(world.playerPosition == gate)
        #expect(movement.isMoving == false)
    }

    @Test func enteringGateEmitsGateEventAndStops() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 0, y: 1, story: 0)
        let wall = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: wall)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, wall])

        let events = movement.update(deltaTime: 10, world: &world)
        #expect(events.contains(.gate(gate: wall, approach: start)))
        #expect(world.playerPosition == wall)
        #expect(movement.isMoving == false)
    }

    private func screenDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
