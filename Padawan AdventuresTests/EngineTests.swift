import CoreGraphics
import Testing
@testable import Padawan_Adventures

enum TestWorldFactory {
    static func emptyFloor(width: Int, height: Int, stories: Int = 2) -> GameWorld {
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
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 2, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 3, story: 0))

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
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 2, story: 0))

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
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true, hasLadder: false)), at: GridCoord(x: 1, y: 1, story: 0))

        let start = GridCoord(x: 0, y: 1, story: 0)
        let goal = GridCoord(x: 2, y: 1, story: 0)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        let doorCell = GridCoord(x: 1, y: 1, story: 0)
        #expect(path != nil)
        #expect(path?.contains(doorCell) == true)
    }

    @Test func rampConnectsStories() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .ramp(partner: b, otherStory: 1)), at: a)
        world.setTile(Tile(kind: .ramp(partner: a, otherStory: 1)), at: b)

        let start = GridCoord(x: 1, y: 1, story: 0)
        let goal = GridCoord(x: 1, y: 1, story: 1)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
        #expect(path?.last == goal)
    }

    @Test func generatedRampsCarveWalkableUpperLandings() throws {
        let config = WorldSeedConfig(
            version: 1,
            seed: 42,
            world: .init(width: 40, height: 40, stories: 2),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: 20,
                corridorWidth: 2,
                minRoomSize: 4,
                maxRoomSize: 10,
                pitChance: 0,
                wallDestructibleChance: 0,
                rampCount: 8,
                ladderCount: 0,
                slideCount: 0,
                doorCount: 4
            ),
            player: .init(letter: "P", spawn: .init(x: 1, y: 1, story: 0)),
            extensions: nil
        )
        let world = try ProceduralGenerator().generate(from: config)
        var rampTiles = 0
        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: 0)
                guard case .ramp(let partner, let otherStory) = world.tile(at: coord)?.kind else {
                    continue
                }
                rampTiles += 1
                #expect(otherStory == 1)
                #expect(world.isWalkable(at: coord.onStory(1)))
                #expect(world.isWalkable(at: partner.onStory(1)))
            }
        }
        #expect(rampTiles >= 2)
    }

    @Test func ladderConnectsStories() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: GridCoord(x: 1, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: GridCoord(x: 1, y: 1, story: 1))

        let start = GridCoord(x: 0, y: 1, story: 0)
        let goal = GridCoord(x: 0, y: 1, story: 1)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
        #expect(path?.last == goal)
        #expect(path?.contains(GridCoord(x: 1, y: 1, story: 0)) == true)
        #expect(path?.contains(GridCoord(x: 1, y: 1, story: 1)) == true)
    }

    @Test func tappingLadderPathsToOtherStory() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let ladder0 = GridCoord(x: 1, y: 1, story: 0)
        let ladder1 = GridCoord(x: 1, y: 1, story: 1)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: ladder0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: ladder1)

        let start = GridCoord(x: 0, y: 1, story: 0)
        #expect(world.isValidMovementGoal(at: ladder0))
        let resolved = world.movementGoalResolvingConnectors(from: start, goal: ladder0)
        #expect(resolved == ladder1)

        let path = pathfinder.findPath(from: start, to: resolved, in: world)
        #expect(path?.last == ladder1)
        #expect(path?.contains(ladder0) == true)
    }

    @Test func tappingRampPathsToUpperStory() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .ramp(partner: b, otherStory: 1)), at: a)
        world.setTile(Tile(kind: .ramp(partner: a, otherStory: 1)), at: b)

        let start = GridCoord(x: 0, y: 1, story: 0)
        let resolved = world.movementGoalResolvingConnectors(from: start, goal: a)
        #expect(resolved == a.onStory(1))

        let path = pathfinder.findPath(from: start, to: resolved, in: world)
        #expect(path?.last == a.onStory(1))
        #expect(path?.contains(a) == true)
    }

    @Test func rampAllowsDescentFromUpperStory() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .ramp(partner: b, otherStory: 1)), at: a)
        world.setTile(Tile(kind: .ramp(partner: a, otherStory: 1)), at: b)

        let start = GridCoord(x: 1, y: 1, story: 1)
        let goal = GridCoord(x: 0, y: 1, story: 0)
        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
        #expect(path?.contains(a) == true)
        #expect(path?.last == goal)
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
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 1, y: 0, story: 0)
        )

        let start = GridCoord(x: 0, y: 0, story: 0)
        let neighbors = pathfinder.neighbors(of: start, in: world)
        #expect(!neighbors.contains(GridCoord(x: 1, y: 1, story: 0)))
        #expect(neighbors.contains(GridCoord(x: 0, y: 1, story: 0)))
    }

    @Test func doorAndPitAreInvalidGoals() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let door = GridCoord(x: 1, y: 1, story: 0)
        let pit = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true, hasLadder: false)), at: door)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)

        let start = GridCoord(x: 0, y: 1, story: 0)
        #expect(pathfinder.findPath(from: start, to: door, in: world) == nil)
        #expect(pathfinder.findPath(from: start, to: pit, in: world) == nil)
    }

    @Test func slideAllowsDownOnly() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let upperA = GridCoord(x: 1, y: 1, story: 1)
        let upperB = GridCoord(x: 2, y: 1, story: 1)
        world.setTile(Tile(kind: .slide(partner: upperB, lowerStory: 0)), at: upperA)
        world.setTile(Tile(kind: .slide(partner: upperA, lowerStory: 0)), at: upperB)

        let downPath = pathfinder.findPath(from: upperA, to: GridCoord(x: 1, y: 1, story: 0), in: world)
        #expect(downPath != nil)
        #expect(downPath?.last == GridCoord(x: 1, y: 1, story: 0))

        let lowerStart = GridCoord(x: 1, y: 1, story: 0)
        let upPath = pathfinder.findPath(from: lowerStart, to: upperA, in: world)
        #expect(upPath != nil)
        #expect(upPath?.last != upperA)
        #expect(upPath?.last?.story == 0)
    }

    @Test func destroyWallOpensRoute() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        world.setTile(Tile(kind: .wall(destructible: true, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall(destructible: true, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 2, story: 0))

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
    @Test func validGoalsAreNonPitFloorsRampsAndSlides() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let floor = GridCoord(x: 0, y: 0, story: 0)
        let pit = GridCoord(x: 1, y: 0, story: 0)
        let wall = GridCoord(x: 2, y: 0, story: 0)
        let door = GridCoord(x: 0, y: 1, story: 0)
        let ramp = GridCoord(x: 1, y: 1, story: 0)
        let slide = GridCoord(x: 2, y: 1, story: 0)
        let ladder = GridCoord(x: 0, y: 2, story: 0)
        let partner = GridCoord(x: 1, y: 2, story: 0)

        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: wall)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true, hasLadder: false)), at: door)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: ladder)
        world.setTile(Tile(kind: .ramp(partner: partner, otherStory: 1)), at: ramp)
        world.setTile(Tile(kind: .slide(partner: partner, lowerStory: 0)), at: slide)

        #expect(world.isValidMovementGoal(at: floor))
        #expect(world.isValidMovementGoal(at: ramp))
        #expect(world.isValidMovementGoal(at: slide))
        #expect(world.isValidMovementGoal(at: ladder))
        #expect(!world.isValidMovementGoal(at: pit))
        #expect(!world.isValidMovementGoal(at: wall))
        #expect(!world.isValidMovementGoal(at: door))
    }

    @Test func nearestValidMovementGoalSnapsFromWall() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let wall = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: wall)

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
    @Test func pitFallsToLowerStory() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.setTile(Tile(kind: .floor(isPit: true)), at: GridCoord(x: 1, y: 1, story: 1))
        world.setPlayerPosition(GridCoord(x: 1, y: 1, story: 1))

        let resolution = world.resolvePit(at: GridCoord(x: 1, y: 1, story: 1))
        #expect(resolution == .fell(to: GridCoord(x: 1, y: 1, story: 0)))
        #expect(world.playerPosition == GridCoord(x: 1, y: 1, story: 0))
    }

    @Test func pitWithoutLowerTileIsHazard() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 1, y: 1, story: 0))
        world.setTile(Tile(kind: .floor(isPit: true)), at: GridCoord(x: 1, y: 1, story: 1))
        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 1))

        let resolution = world.resolvePit(at: GridCoord(x: 1, y: 1, story: 1))
        #expect(resolution == .hazard)
        #expect(world.playerPosition == world.spawn)
    }
}

struct MovementSystemTests {
    @Test func pathDurationMatchesSpeed() {
        var movement = MovementSystem()
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

        var movement = MovementSystem()
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

    @Test func ladderSegmentInterpolatesScreenYContinuously() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 1, y: 1, story: 0)
        let end = GridCoord(x: 1, y: 1, story: 1)
        world.setPlayerPosition(start)

        var movement = MovementSystem()
        movement.begin(path: [start, end])

        let config = IsometricConfig()
        let from = IsometricMath.entityScreenPosition(start, config: config)
        let to = IsometricMath.entityScreenPosition(end, config: config)

        _ = movement.update(deltaTime: 0.25, world: &world)
        let mid = movement.interpolatedScreenPosition(in: world, config: config)
        #expect(abs(mid.x - from.x) < 0.000_001)
        #expect(mid.y > from.y)
        #expect(mid.y < to.y)

        _ = movement.update(deltaTime: 0.25, world: &world)
        let later = movement.interpolatedScreenPosition(in: world, config: config)
        #expect(later.y > mid.y)
        #expect(later.y <= to.y)
    }

    @Test func slideDescentIsTwiceAsFast() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let upper = GridCoord(x: 1, y: 1, story: 1)
        let lower = GridCoord(x: 1, y: 1, story: 0)
        let partner = GridCoord(x: 2, y: 1, story: 1)
        world.setTile(Tile(kind: .slide(partner: partner, lowerStory: 0)), at: upper)
        world.setTile(Tile(kind: .slide(partner: upper, lowerStory: 0)), at: partner)
        world.setPlayerPosition(upper)

        let slidePath = [upper, lower]
        let walkPath = [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 1, y: 0, story: 0),
        ]

        var movement = MovementSystem(tilesPerSecond: 1.0)
        #expect(movement.totalDuration(for: walkPath, in: world) == 1.0)
        #expect(movement.totalDuration(for: slidePath, in: world) == 0.5)

        movement.begin(path: slidePath)
        _ = movement.update(deltaTime: 0.49, world: &world)
        #expect(movement.isMoving == true)
        _ = movement.update(deltaTime: 0.02, world: &world)
        #expect(world.playerPosition == lower)
        #expect(movement.isMoving == false)
    }

    private func screenDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
