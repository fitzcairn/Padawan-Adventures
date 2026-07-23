import Testing
@testable import Padawan_Adventures

struct PickupContactTests {
    @Test func pickupInContactWithPlayer() {
        let spawn = GridCoord(x: 0, y: 0, story: 0)
        let pickupPos = GridCoord(x: 1, y: 0, story: 0)
        let player = GameEntity(letter: "P", position: pickupPos, isPlayer: true)
        let health = GameEntity(letter: " ", position: pickupPos, pickupKind: .health)
        let world = GameWorld(
            width: 3,
            height: 3,
            tiles: TestWorldFactory.emptyFloor(width: 3, height: 3).tiles,
            entities: [player, health],
            spawn: spawn
        )

        #expect(world.pickupInContactWithPlayer()?.pickupKind == .health)
        #expect(world.enemyInContactWithPlayer() == nil)
    }

    @Test func simulationReportsPickupContactWhenNoEnemy() {
        let spawn = GridCoord(x: 0, y: 0, story: 0)
        let player = GameEntity(letter: "P", position: spawn, isPlayer: true)
        let energy = GameEntity(letter: " ", position: spawn, pickupKind: .energy)
        var world = GameWorld(
            width: 3,
            height: 3,
            tiles: TestWorldFactory.emptyFloor(width: 3, height: 3).tiles,
            entities: [player, energy],
            spawn: spawn
        )
        var movement = MovementSystem()
        var pending = PendingInput()
        var loop = SimulationLoop()

        let result = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pending,
            tickCount: 1
        )
        #expect(result.pickupContactID == energy.id)
        #expect(result.enemyContactID == nil)
    }
}
