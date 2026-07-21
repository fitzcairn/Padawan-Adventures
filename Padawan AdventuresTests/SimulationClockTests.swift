import Foundation
import Testing
@testable import Padawan_Adventures

struct SimulationClockTests {
    @Test func tickDurationIs15fps() {
        #expect(abs(SimulationClock.tickDuration - (1.0 / 15.0)) < 0.000_001)
    }

    @Test func advanceEmitsTicksAtRate() {
        var clock = SimulationClock()
        clock.maxCatchUpTicks = 20
        clock.maxFrameDelta = 1.0
        let ticks = clock.advance(deltaTime: 1.0)
        #expect(ticks == 15)
    }

    @Test func accumulatorCarriesRemainder() {
        var clock = SimulationClock()
        let first = clock.advance(deltaTime: SimulationClock.tickDuration * 1.5)
        #expect(first == 1)

        let second = clock.advance(deltaTime: SimulationClock.tickDuration * 0.6)
        #expect(second == 1)
    }

    @Test func catchUpIsCapped() {
        var clock = SimulationClock()
        clock.maxCatchUpTicks = 5
        clock.maxFrameDelta = 10.0
        let ticks = clock.advance(deltaTime: 10.0)
        #expect(ticks == 5)
    }
}

struct SimulationLoopTests {
    @Test func controlsConsumedOnTick() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        var movement = MovementSystem()
        var pendingInput = PendingInput()
        var loop = SimulationLoop()

        pendingInput.enqueue(GridCoord(x: 2, y: 0, story: 0))
        #expect(pendingInput.destination != nil)

        _ = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 1
        )

        #expect(pendingInput.destination == nil)
        #expect(movement.isMoving)
    }

    @Test func positionsAdvanceOneTickDuration() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        var movement = MovementSystem()
        var pendingInput = PendingInput()
        var loop = SimulationLoop()

        movement.begin(path: [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 1, y: 0, story: 0),
        ])

        let start = movement.interpolatedScreenPosition(in: world)
        let result = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 1
        )

        #expect(movement.isMoving)
        #expect(movement.segmentProgress > 0)
        #expect(movement.interpolatedScreenPosition(in: world) != start)
        #expect(result.playerDisplayPoint != nil)
        #expect(result.playerDisplayPoint != start)
    }

    @Test func newTapReplacesInFlightPath() {
        var world = TestWorldFactory.emptyFloor(width: 6, height: 4)
        var movement = MovementSystem()
        var pendingInput = PendingInput()
        var loop = SimulationLoop()

        movement.begin(path: [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 1, y: 0, story: 0),
            GridCoord(x: 2, y: 0, story: 0),
            GridCoord(x: 3, y: 0, story: 0),
        ])

        // Advance past the border so occupancy is tile (1,0).
        _ = movement.update(deltaTime: 2.6, world: &world)
        #expect(world.playerPosition == GridCoord(x: 1, y: 0, story: 0))

        pendingInput.enqueue(GridCoord(x: 1, y: 2, story: 0))
        _ = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 1
        )

        #expect(movement.isMoving)
        #expect(movement.path.first == GridCoord(x: 1, y: 0, story: 0))
        #expect(movement.path.last == GridCoord(x: 1, y: 2, story: 0))
    }

    @Test func unreachableGoalPathsClosestViaControls() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), at: GridCoord(x: 2, y: 2, story: 0))

        var movement = MovementSystem()
        var pendingInput = PendingInput()
        var loop = SimulationLoop()

        pendingInput.enqueue(GridCoord(x: 4, y: 1, story: 0))
        _ = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 1
        )

        #expect(movement.isMoving)
        #expect(movement.path.last == GridCoord(x: 1, y: 1, story: 0))
    }

    @Test func persistOnlyWhenSettled() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        var movement = MovementSystem()
        var pendingInput = PendingInput()
        var loop = SimulationLoop()

        movement.begin(path: [
            GridCoord(x: 0, y: 0, story: 0),
            GridCoord(x: 2, y: 0, story: 0),
        ])

        let midTick = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 1
        )
        #expect(midTick.shouldPersist == false)

        var settled = SimulationTickResult()
        var tickCount: UInt64 = 2
        while movement.isMoving {
            settled = loop.tick(
                world: &world,
                movement: &movement,
                pendingInput: &pendingInput,
                tickCount: tickCount
            )
            tickCount += 1
        }

        #expect(settled.shouldPersist == true)
        #expect(world.playerPosition == GridCoord(x: 2, y: 0, story: 0))
    }
}
