import Testing
@testable import Padawan_Adventures

struct PathfinderTests {
    @Test func findsPathAroundWall() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 2, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 3, story: 0))

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
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 2, story: 0))

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

    @Test func gatesArePassableGoals() {
        let pathfinder = Pathfinder()
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let gate = GridCoord(x: 1, y: 1, story: 0)
        let soft = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: gate)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: soft)

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
            Tile(kind: .wall),
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
        world.setTile(Tile(kind: .wall), at: wall)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)

        let start = GridCoord(x: 0, y: 1, story: 0)
        #expect(pathfinder.findPath(from: start, to: wall, in: world) == nil)

        let pitPath = pathfinder.findPath(from: start, to: pit, in: world)
        #expect(pitPath != nil)
        #expect(pitPath?.last == pit)
    }

    @Test func openGateConvertsGateToFloor() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let soft = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: soft)

        let opened = world.openGate(at: soft)
        #expect(opened == [soft])
        if case .floor(let isPit) = world.tile(at: soft)?.kind {
            #expect(!isPit)
        } else {
            Issue.record("Expected floor after openGate")
        }
        let openedAgain = world.openGate(at: soft)
        #expect(openedAgain.isEmpty)
    }

    @Test func openGateClearsContiguousGateGroup() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: a)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: b)

        let opened = world.openGate(at: a)
        #expect(Set(opened) == [a, b])
        #expect(world.tile(at: a)?.isGate == false)
        #expect(world.tile(at: b)?.isGate == false)
        #expect(world.isEnterable(at: a))
        #expect(world.isEnterable(at: b))
    }

    @Test func openGateClearsContiguousStrip() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let a = GridCoord(x: 1, y: 1, story: 0)
        let b = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: a)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: b)

        let opened = world.openGate(at: a)
        #expect(Set(opened) == [a, b])
        #expect(world.tile(at: a)?.isGate == false)
        #expect(world.tile(at: b)?.isGate == false)
        #expect(world.isEnterable(at: a))
        #expect(world.isEnterable(at: b))
    }

    @Test func openGateClearsOnlySameMinigameKind() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let spelling = GridCoord(x: 1, y: 1, story: 0)
        let graphemeMatch = GridCoord(x: 2, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: spelling)
        world.setTile(Tile(kind: .gate(minigame: .graphemeMatch)), at: graphemeMatch)

        let opened = world.openGate(at: spelling)
        #expect(opened == [spelling])
        #expect(world.tile(at: spelling)?.isGate == false)
        #expect(world.tile(at: graphemeMatch)?.gateMinigame == .graphemeMatch)
    }
}
