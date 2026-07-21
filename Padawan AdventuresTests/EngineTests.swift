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

    @Test func ladderConnectsStories() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: GridCoord(x: 1, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true)), at: GridCoord(x: 1, y: 1, story: 1))

        // Ladder cells are not valid goals; path to a floor on the other story via the ladder.
        let start = GridCoord(x: 0, y: 1, story: 0)
        let goal = GridCoord(x: 0, y: 1, story: 1)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
        #expect(path?.last == goal)
        #expect(path?.contains(GridCoord(x: 1, y: 1, story: 0)) == true)
        #expect(path?.contains(GridCoord(x: 1, y: 1, story: 1)) == true)
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
        let partner = GridCoord(x: 1, y: 2, story: 0)

        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: wall)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: true, hasLadder: false)), at: door)
        world.setTile(Tile(kind: .ramp(partner: partner, otherStory: 1)), at: ramp)
        world.setTile(Tile(kind: .slide(partner: partner, lowerStory: 0)), at: slide)

        #expect(world.isValidMovementGoal(at: floor))
        #expect(world.isValidMovementGoal(at: ramp))
        #expect(world.isValidMovementGoal(at: slide))
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
}
