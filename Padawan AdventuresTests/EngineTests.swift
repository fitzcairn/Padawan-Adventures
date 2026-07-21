import CoreGraphics
import Testing
@testable import Padawan_Adventures

enum TestWorldFactory {
    static func emptyFloor(width: Int, height: Int, stories: Int = 1) -> GameWorld {
        let floor = Tile(kind: .floor(isPit: false))
        let tiles = Array(
            repeating: Array(repeating: Array(repeating: floor, count: width), count: height),
            count: stories
        )
        let spawn = GridCoord(x: 0, y: 0, story: 0)
        let player = GameEntity(letter: "P", position: spawn, isPlayer: true)
        return GameWorld(width: width, height: height, storyCount: stories, tiles: tiles, entities: [player], spawn: spawn)
    }

    static func withTiles(_ tiles: [[[Tile]]], spawn: GridCoord) -> GameWorld {
        let stories = tiles.count
        let height = tiles[0].count
        let width = tiles[0][0].count
        let player = GameEntity(letter: "P", position: spawn, isPlayer: true)
        return GameWorld(width: width, height: height, storyCount: stories, tiles: tiles, entities: [player], spawn: spawn)
    }
}

struct PathfinderTests {
    @Test func findsPathAroundWall() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: GridCoord(x: 2, y: 2, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: GridCoord(x: 2, y: 3, story: 0))

        let start = GridCoord(x: 1, y: 2, story: 0)
        let goal = GridCoord(x: 3, y: 2, story: 0)
        world.setPlayerPosition(start)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        let blocked = GridCoord(x: 2, y: 2, story: 0)
        #expect(path != nil)
        #expect(path?.first == start)
        #expect(path?.last == goal)
        #expect(path?.contains(blocked) == false)
    }

    @Test func cannotPathThroughSolidWallPathsToClosest() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: GridCoord(x: 2, y: 2, story: 0))

        let start = GridCoord(x: 0, y: 1, story: 0)
        let goal = GridCoord(x: 4, y: 1, story: 0)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
        #expect(path?.first == start)
        // Closest on the start side under Chebyshev + stable tie-break.
        #expect(path?.last == GridCoord(x: 1, y: 0, story: 0))
        #expect(path?.contains(GridCoord(x: 2, y: 1, story: 0)) == false)
        #expect(path?.contains(goal) == false)
    }

    @Test func doorCellIsPassable() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true)), at: GridCoord(x: 1, y: 1, story: 0))

        let start = GridCoord(x: 0, y: 1, story: 0)
        let goal = GridCoord(x: 2, y: 1, story: 0)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        let doorCell = GridCoord(x: 1, y: 1, story: 0)
        #expect(path != nil)
        #expect(path?.contains(doorCell) == true)
    }

    @Test func findsDiagonalShortcutOnOpenFloor() {
        let pathfinder = Pathfinder()
        let world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let start = GridCoord(x: 0, y: 0, story: 0)
        let goal = GridCoord(x: 2, y: 2, story: 0)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
        #expect(path?.count == 3) // start → diagonal → goal
        #expect(path?.contains(GridCoord(x: 1, y: 1, story: 0)) == true)
    }

    @Test func diagonalBlockedByCornerWall() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        // Block one cardinal adjacent to the diagonal from (0,0) → (1,1).
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false)),
            at: GridCoord(x: 1, y: 0, story: 0)
        )

        let start = GridCoord(x: 0, y: 0, story: 0)
        let neighbors = pathfinder.neighbors(of: start, in: world)
        #expect(!neighbors.contains(GridCoord(x: 1, y: 1, story: 0)))
        #expect(neighbors.contains(GridCoord(x: 0, y: 1, story: 0)))
    }

    @Test func doorIsInvalidGoalButPitIsReachable() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let door = GridCoord(x: 1, y: 1, story: 0)
        let pit = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true)), at: door)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)

        let start = GridCoord(x: 0, y: 1, story: 0)
        #expect(pathfinder.findPath(from: start, to: door, in: world) == nil)

        let pitPath = pathfinder.findPath(from: start, to: pit, in: world)
        #expect(pitPath != nil)
        #expect(pitPath?.last == pit)
    }

    @Test func destroyWallOpensRoute() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        world.setTile(Tile(kind: .wall(destructible: true, hasDoor: false)), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall(destructible: true, hasDoor: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: GridCoord(x: 2, y: 2, story: 0))

        let start = GridCoord(x: 0, y: 1, story: 0)
        let goal = GridCoord(x: 4, y: 1, story: 0)

        let blocked = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(blocked != nil)
        #expect(blocked?.last != goal)

        let destroyed = world.destroyWall(at: GridCoord(x: 2, y: 1, story: 0))
        #expect(destroyed)
        let opened = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(opened != nil)
        #expect(opened?.last == goal)
    }
}

struct MovementGoalTests {
    @Test func validGoalsIncludeFloorsAndPitsOnly() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let floor = GridCoord(x: 0, y: 0, story: 0)
        let pit = GridCoord(x: 1, y: 0, story: 0)
        let wall = GridCoord(x: 2, y: 0, story: 0)
        let door = GridCoord(x: 0, y: 1, story: 0)

        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: wall)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true)), at: door)

        #expect(world.isValidMovementGoal(at: floor))
        #expect(world.isValidMovementGoal(at: pit))
        #expect(!world.isValidMovementGoal(at: wall))
        #expect(!world.isValidMovementGoal(at: door))
    }

    @Test func nearestValidMovementGoalSnapsFromWall() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let wall = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false)), at: wall)

        let goal = world.nearestValidMovementGoal(from: wall)
        #expect(goal != nil)
        #expect(goal != wall)
        if let goal {
            #expect(world.isValidMovementGoal(at: goal))
            #expect(abs(goal.x - wall.x) + abs(goal.y - wall.y) == 1)
        }
    }

    @Test func nearestValidMovementGoalReturnsSelfWhenAlreadyValid() {
        let world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let floor = GridCoord(x: 1, y: 1, story: 0)
        #expect(world.nearestValidMovementGoal(from: floor) == floor)
    }
}

struct PitResolutionTests {
    @Test func pitIsAlwaysHazard() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(pit)

        let resolution = world.resolvePit(at: pit)
        #expect(resolution == .hazard)
        #expect(world.playerPosition == pit)
    }

    @Test func enteringHazardPitStopsMovementAndStaysOnPit() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 0, y: 1, story: 0)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, pit])

        let events = movement.update(deltaTime: 10, world: &world)
        #expect(events.contains(.pit(.hazard)))
        #expect(world.playerPosition == pit)
        #expect(movement.isMoving == false)
    }
}

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

    private func screenDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

struct PickupContactTests {
    @Test func pickupInContactWithPlayer() {
        let spawn = GridCoord(x: 0, y: 0, story: 0)
        let pickupPos = GridCoord(x: 1, y: 0, story: 0)
        let player = GameEntity(letter: "P", position: pickupPos, isPlayer: true)
        let health = GameEntity(letter: " ", position: pickupPos, pickupKind: .health)
        let world = GameWorld(
            width: 3,
            height: 3,
            tiles: TestWorldFactory.emptyFloor(width: 3, height: 3).tiles,
            entities: [player, health],
            spawn: spawn
        )

        #expect(world.pickupInContactWithPlayer()?.pickupKind == .health)
        #expect(world.enemyInContactWithPlayer() == nil)
    }

    @Test func simulationReportsPickupContactWhenNoEnemy() {
        let spawn = GridCoord(x: 0, y: 0, story: 0)
        let player = GameEntity(letter: "P", position: spawn, isPlayer: true)
        let energy = GameEntity(letter: " ", position: spawn, pickupKind: .energy)
        var world = GameWorld(
            width: 3,
            height: 3,
            tiles: TestWorldFactory.emptyFloor(width: 3, height: 3).tiles,
            entities: [player, energy],
            spawn: spawn
        )
        var movement = MovementSystem()
        var pending = PendingInput()
        var loop = SimulationLoop()

        let result = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pending,
            tickCount: 1
        )
        #expect(result.pickupContactID == energy.id)
        #expect(result.enemyContactID == nil)
    }
}
