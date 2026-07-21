import Testing
@testable import Padawan_Adventures

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
