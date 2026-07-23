import Testing
@testable import Padawan_Adventures

struct PathfinderTests {
    @Test func findsPathAroundWall() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        world.setTile(Tile(kind: .wall(destructible: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false)), at: GridCoord(x: 2, y: 2, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false)), at: GridCoord(x: 2, y: 3, story: 0))

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
        world.setTile(Tile(kind: .wall(destructible: false)), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false)), at: GridCoord(x: 2, y: 2, story: 0))

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

    @Test func gateAndDestructibleArePassableGoals() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let gate = GridCoord(x: 1, y: 1, story: 0)
        let soft = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .gate), at: gate)
        world.setTile(Tile(kind: .wall(destructible: true)), at: soft)

        let start = GridCoord(x: 0, y: 1, story: 0)
        let goal = GridCoord(x: 4, y: 1, story: 0)

        let path = pathfinder.findPath(from: start, to: goal, in: world)
        #expect(path != nil)
        #expect(path?.contains(gate) == true)
        #expect(path?.contains(soft) == true)
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
            Tile(kind: .wall(destructible: false)),
            at: GridCoord(x: 1, y: 0, story: 0)
        )

        let start = GridCoord(x: 0, y: 0, story: 0)
        let neighbors = pathfinder.neighbors(of: start, in: world)
        #expect(!neighbors.contains(GridCoord(x: 1, y: 1, story: 0)))
        #expect(neighbors.contains(GridCoord(x: 0, y: 1, story: 0)))
    }

    @Test func solidWallIsInvalidGoalButPitIsReachable() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let wall = GridCoord(x: 1, y: 1, story: 0)
        let pit = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: false)), at: wall)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)

        let start = GridCoord(x: 0, y: 1, story: 0)
        #expect(pathfinder.findPath(from: start, to: wall, in: world) == nil)

        let pitPath = pathfinder.findPath(from: start, to: pit, in: world)
        #expect(pitPath != nil)
        #expect(pitPath?.last == pit)
    }

    @Test func destroyWallConvertsDestructibleToFloor() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let soft = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: true)), at: soft)

        let destroyed = world.destroyWall(at: soft)
        #expect(destroyed)
        if case .floor(let isPit) = world.tile(at: soft)?.kind {
            #expect(!isPit)
        } else {
            Issue.record("Expected floor after destroyWall")
        }
        let destroyedAgain = world.destroyWall(at: soft)
        #expect(!destroyedAgain)
    }

    @Test func destroyWallClearsContiguousSoftWallGroup() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .wall(destructible: true)), at: a)
        world.setTile(Tile(kind: .wall(destructible: true)), at: b)

        let destroyed = world.destroyWall(at: a)
        #expect(destroyed)
        #expect(world.tile(at: a)?.isDestructibleWall == false)
        #expect(world.tile(at: b)?.isDestructibleWall == false)
        #expect(world.isEnterable(at: a))
        #expect(world.isEnterable(at: b))
    }

    @Test func openGateClearsContiguousStrip() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .gate), at: a)
        world.setTile(Tile(kind: .gate), at: b)

        let opened = world.openGate(at: a)
        #expect(opened)
        #expect(world.tile(at: a)?.isGate == false)
        #expect(world.tile(at: b)?.isGate == false)
        #expect(world.isEnterable(at: a))
        #expect(world.isEnterable(at: b))
    }
}
