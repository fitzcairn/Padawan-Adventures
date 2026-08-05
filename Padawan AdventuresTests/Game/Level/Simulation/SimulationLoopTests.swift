import Foundation
import Testing
@testable import Padawan_Adventures

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
        _ = movement.update(deltaTime: 0.51, world: &world)
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
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 0, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 1, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 2, y: 2, story: 0))

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
        #expect(movement.path.last == GridCoord(x: 1, y: 0, story: 0))
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

    @Test func gateContactSurfacesApproachCoord() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 0, y: 1, story: 0)
        let gate = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: gate)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        var pendingInput = PendingInput()
        var loop = SimulationLoop()
        movement.begin(path: [start, gate])

        var result = SimulationTickResult()
        var tickCount: UInt64 = 1
        while result.gateCoord == nil, tickCount < 100 {
            result = loop.tick(
                world: &world,
                movement: &movement,
                pendingInput: &pendingInput,
                tickCount: tickCount
            )
            tickCount += 1
        }

        #expect(result.gateCoord == gate)
        #expect(result.gateApproachCoord == start)
        #expect(result.hasEncounterContact)
    }

    /// Walking onto a pit an enemy is standing on reports both a pit entry and a contact.
    /// The caller only acts on the pit, so the loop must not freeze on the unused contact.
    private func pitEntryWithEnemyOnPit() -> (
        world: GameWorld,
        loop: SimulationLoop,
        movement: MovementSystem,
        pendingInput: PendingInput,
        approach: GridCoord,
        enemyID: UUID
    ) {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let approach = GridCoord(x: 0, y: 1, story: 0)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(approach)

        let enemy = GameEntity(letter: "E", position: pit, isPlayer: false, enemyTypeID: "spider")
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: [world.entities[0], enemy],
            spawn: world.spawn
        )
        let enemyID = enemy.id

        var loop = SimulationLoop(enemyConfig: .fallback)
        var movement = MovementSystem()
        var pendingInput = PendingInput()
        movement.begin(path: [approach, pit])

        var result = SimulationTickResult()
        var tickCount: UInt64 = 1
        while !result.didEnterPit, tickCount < 100 {
            result = loop.tick(
                world: &world,
                movement: &movement,
                pendingInput: &pendingInput,
                tickCount: tickCount
            )
            tickCount += 1
        }
        #expect(result.didEnterPit)
        #expect(result.enemyContactID == enemyID)

        // Stand in for the pit resolver: retreat the player and hand the world back.
        world.setPlayerPosition(approach)
        movement.reset()

        return (world, loop, movement, pendingInput, approach, enemyID)
    }

    @Test func pitEntryOverEnemyKeepsControlsResponsive() {
        var (world, loop, movement, pendingInput, _, _) = pitEntryWithEnemyOnPit()

        pendingInput.enqueue(GridCoord(x: 0, y: 2, story: 0))
        _ = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 200
        )

        #expect(pendingInput.destination == nil)
        #expect(movement.isMoving)
        #expect(movement.path.last == GridCoord(x: 0, y: 2, story: 0))
    }

    @Test func pitEntryOverEnemyKeepsEnemyAIRunning() {
        var (world, loop, movement, pendingInput, _, enemyID) = pitEntryWithEnemyOnPit()

        // The enemy still has line of sight, so it should close in and reach contact.
        var contactID: UUID?
        var tickCount: UInt64 = 200
        while contactID == nil, tickCount < 400 {
            contactID = loop.tick(
                world: &world,
                movement: &movement,
                pendingInput: &pendingInput,
                tickCount: tickCount
            ).enemyContactID
            tickCount += 1
        }

        #expect(contactID == enemyID)
    }

    @Test func dispatchedContactFreezesUntilEnemyRemoved() {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 3)
        let tile = GridCoord(x: 1, y: 1, story: 0)
        world.setPlayerPosition(tile)
        let enemy = GameEntity(letter: "E", position: tile, isPlayer: false, enemyTypeID: "spider")
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: [world.entities[0], enemy],
            spawn: world.spawn
        )

        var loop = SimulationLoop(enemyConfig: .fallback)
        var movement = MovementSystem()
        var pendingInput = PendingInput()

        let contact = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 1
        )
        #expect(contact.enemyContactID == enemy.id)
        loop.beginEnemyEncounter()

        // Frozen: taps are held, not consumed, while the fight runs.
        pendingInput.enqueue(GridCoord(x: 3, y: 1, story: 0))
        _ = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 2
        )
        #expect(pendingInput.destination != nil)
        #expect(movement.isMoving == false)

        loop.removeEnemy(id: enemy.id, from: &world)
        _ = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pendingInput,
            tickCount: 3
        )
        #expect(pendingInput.destination == nil)
        #expect(movement.isMoving)
    }
}
