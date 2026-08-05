import Testing
@testable import Padawan_Adventures

struct MovementGoalTests {
    @Test func validGoalsIncludeFloorsPitsAndGates() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 3)
        let floor = GridCoord(x: 0, y: 0, story: 0)
        let pit = GridCoord(x: 1, y: 0, story: 0)
        let wall = GridCoord(x: 2, y: 0, story: 0)
        let soft = GridCoord(x: 3, y: 0, story: 0)
        let gate = GridCoord(x: 0, y: 1, story: 0)

        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setTile(Tile(kind: .wall), at: wall)
        world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: soft)
        world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: gate)

        #expect(world.isValidMovementGoal(at: floor))
        #expect(world.isValidMovementGoal(at: pit))
        #expect(!world.isValidMovementGoal(at: wall))
        #expect(world.isValidMovementGoal(at: soft))
        #expect(world.isValidMovementGoal(at: gate))
    }

    @Test func nearestValidMovementGoalSnapsFromSolidWall() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let wall = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .wall), at: wall)

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
