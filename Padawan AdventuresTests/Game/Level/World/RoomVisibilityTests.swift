import Testing
@testable import Padawan_Adventures

struct RoomVisibilityTests {
    /// Two 1x3 rooms in columns 0 and 4, sealed by a 2-cell gate strip at x = 2.
    /// Column 1 and 3 are solid wall, so the gate is the only join.
    private func twoRoomWorld(gate: GateMinigameKind = .spelling) -> GameWorld {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        for y in 0..<3 {
            world.setTile(Tile(kind: .wall), at: GridCoord(x: 1, y: y, story: 0))
            world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: y, story: 0))
            world.setTile(Tile(kind: .wall), at: GridCoord(x: 3, y: y, story: 0))
        }
        world.setTile(Tile(kind: .gate(minigame: gate)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .floor(isPit: false)), at: GridCoord(x: 1, y: 1, story: 0))
        world.setTile(Tile(kind: .floor(isPit: false)), at: GridCoord(x: 3, y: 1, story: 0))
        world.setPlayerPosition(GridCoord(x: 0, y: 1, story: 0))
        return world
    }

    @Test func closedGateHidesTheRoomBehindIt() {
        let world = twoRoomWorld()
        let result = RoomVisibility.compute(in: world, story: 0, from: world.playerPosition)

        #expect(result.floorCells.contains(GridCoord(x: 0, y: 1, story: 0)))
        #expect(result.floorCells.contains(GridCoord(x: 1, y: 1, story: 0)))
        // Approach floor on the far side of the gate and the far room stay dark.
        #expect(!result.floorCells.contains(GridCoord(x: 3, y: 1, story: 0)))
        #expect(!result.floorCells.contains(GridCoord(x: 4, y: 1, story: 0)))
    }

    @Test func closedGateItselfStaysVisible() {
        let world = twoRoomWorld()
        let result = RoomVisibility.compute(in: world, story: 0, from: world.playerPosition)

        #expect(result.renderableCells.contains(GridCoord(x: 2, y: 1, story: 0)))
        #expect(!result.renderableCells.contains(GridCoord(x: 4, y: 1, story: 0)))
    }

    @Test func openingTheGateRevealsTheRoomBeyond() {
        var world = twoRoomWorld()
        _ = world.openGate(at: GridCoord(x: 2, y: 1, story: 0))
        let result = RoomVisibility.compute(in: world, story: 0, from: world.playerPosition)

        #expect(result.floorCells.contains(GridCoord(x: 2, y: 1, story: 0)))
        #expect(result.floorCells.contains(GridCoord(x: 4, y: 0, story: 0)))
        #expect(result.floorCells.contains(GridCoord(x: 4, y: 2, story: 0)))
    }

    @Test func gateBeyondAHiddenRoomIsNotRendered() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 1)
        let near = GridCoord(x: 1, y: 0, story: 0)
        let far = GridCoord(x: 4, y: 0, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: near)
        world.setTile(Tile(kind: .gate(minigame: .letterMatch)), at: far)
        world.setPlayerPosition(GridCoord(x: 0, y: 0, story: 0))

        let result = RoomVisibility.compute(in: world, story: 0, from: world.playerPosition)
        #expect(result.renderableCells.contains(near))
        #expect(!result.renderableCells.contains(far))
    }

    @Test func playerStandingOnAGateStillLightsTheirRoom() {
        var world = twoRoomWorld()
        let gate = GridCoord(x: 2, y: 1, story: 0)
        world.setPlayerPosition(gate)

        let result = RoomVisibility.compute(in: world, story: 0, from: world.playerPosition)
        #expect(result.floorCells.contains(gate))
        #expect(result.floorCells.contains(GridCoord(x: 0, y: 1, story: 0)))
    }

    @Test func offStoryOrMissingOriginRevealsNothing() {
        let world = twoRoomWorld()
        #expect(RoomVisibility.compute(in: world, story: 1, from: world.playerPosition) == .empty)
        #expect(RoomVisibility.compute(in: world, story: 0, from: nil) == .empty)
    }
}
