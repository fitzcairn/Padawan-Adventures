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
        #expect(path?.last == GridCoord(x: 1, y: 1, story: 0))
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

        let start = GridCoord(x: 1, y: 1, story: 0)
        let goal = GridCoord(x: 1, y: 1, story: 1)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
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
        #expect(duration == 10.0)
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

        // Just under half a tile at 0.2 tiles/s → 2.5s per half segment.
        _ = movement.update(deltaTime: 2.4, world: &world)
        #expect(world.playerPosition == start)
        #expect(movement.segmentProgress < 0.5)

        _ = movement.update(deltaTime: 0.2, world: &world)
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
