import Foundation
import Testing
@testable import Padawan_Adventures

struct EnemyAITests {
    private let enemyConfig = EnemyConfig.fallback

    private func worldWithEnemy(
        playerAt: GridCoord,
        enemyAt: GridCoord,
        width: Int = 8,
        height: Int = 3
    ) -> GameWorld {
        var world = TestWorldFactory.emptyFloor(width: width, height: height)
        world.setPlayerPosition(playerAt)
        let enemy = GameEntity(
            letter: "E",
            position: enemyAt,
            isPlayer: false,
            enemyTypeID: "grunt"
        )
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: [world.entities[0], enemy],
            spawn: world.spawn
        )
        return world
    }

    @Test func idleUntilLineOfSight() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 6, y: 1, story: 0)
        )
        // Wall between them.
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 3, y: 1, story: 0)
        )
        // Block the whole column so pathfinding can't sneak around on this narrow map.
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 3, y: 0, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 3, y: 2, story: 0)
        )

        var ai = EnemyAISystem(enemyConfig: enemyConfig)
        var states: [UUID: EnemyAIState] = [:]
        var movements: [UUID: MovementSystem] = [:]
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: SimulationClock.tickDuration
        )

        #expect(states[enemyID]?.mode == .idle)
        #expect(world.entity(id: enemyID)?.position == GridCoord(x: 6, y: 1, story: 0))
    }

    @Test func chasesPlayerWhenVisible() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 4, y: 1, story: 0)
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        var ai = EnemyAISystem(enemyConfig: enemyConfig)
        var states: [UUID: EnemyAIState] = [:]
        var movements: [UUID: MovementSystem] = [:]

        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: SimulationClock.tickDuration
        )

        #expect(states[enemyID]?.mode == .chasing)
        #expect(states[enemyID]?.chaseGoal == GridCoord(x: 0, y: 1, story: 0))
        #expect(movements[enemyID]?.isMoving == true)
    }

    @Test func chaseGoalTracksPlayerTile() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 5, y: 1, story: 0)
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        var ai = EnemyAISystem(enemyConfig: enemyConfig)
        var states: [UUID: EnemyAIState] = [:]
        var movements: [UUID: MovementSystem] = [:]

        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: SimulationClock.tickDuration
        )
        #expect(states[enemyID]?.chaseGoal == GridCoord(x: 0, y: 1, story: 0))

        world.setPlayerPosition(GridCoord(x: 1, y: 1, story: 0))
        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: SimulationClock.tickDuration
        )
        #expect(states[enemyID]?.chaseGoal == GridCoord(x: 1, y: 1, story: 0))
    }

    @Test func chaseRepathDoesNotJumpScreenPosition() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 6, y: 1, story: 0),
            width: 10,
            height: 5
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        var ai = EnemyAISystem(enemyConfig: enemyConfig)
        var states: [UUID: EnemyAIState] = [:]
        var movements: [UUID: MovementSystem] = [:]

        // Warm up into a mid-segment chase.
        for _ in 0..<8 {
            ai.update(
                world: &world,
                states: &states,
                movements: &movements,
                deltaTime: SimulationClock.tickDuration
            )
        }
        #expect(movements[enemyID]?.isMoving == true)

        let before = movements[enemyID]!.interpolatedScreenPosition(
            in: world,
            entityID: enemyID
        )
        let progressBefore = movements[enemyID]!.segmentProgress
        let nextBefore = movements[enemyID]!.segmentEnd

        // Player steps to a new tile — enemy retargets.
        world.setPlayerPosition(GridCoord(x: 0, y: 2, story: 0))
        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: 0
        )

        let after = movements[enemyID]!.interpolatedScreenPosition(
            in: world,
            entityID: enemyID
        )
        #expect(after == before)

        // If the prior next waypoint is still useful, progress must be preserved.
        if movements[enemyID]?.segmentEnd == nextBefore {
            #expect(abs((movements[enemyID]?.segmentProgress ?? -1) - progressBefore) < 0.000_001)
        }
    }

    @Test func forgetsAfterConfiguredSecondsWithoutSight() {
        // Place a permanent wall column first so LOS cannot reopen while the enemy moves.
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 4, y: 1, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 0, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 1, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 2, story: 0)
        )
        // Open a temporary gap so the enemy can acquire the player, then close it.
        world.setTile(Tile(kind: .floor(isPit: false)), at: GridCoord(x: 2, y: 1, story: 0))

        let enemyID = world.entities.first(where: \.isEnemy)!.id
        var ai = EnemyAISystem(enemyConfig: enemyConfig)
        var states: [UUID: EnemyAIState] = [:]
        var movements: [UUID: MovementSystem] = [:]

        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: SimulationClock.tickDuration
        )
        #expect(states[enemyID]?.mode == .chasing)

        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 1, story: 0)
        )
        #expect(
            LineOfSight.canSee(
                from: world.entity(id: enemyID)!.position,
                to: world.playerPosition!,
                in: world
            ) == false
        )

        ai.update(world: &world, states: &states, movements: &movements, deltaTime: 2.9)
        #expect(states[enemyID]?.mode == .searching)

        ai.update(world: &world, states: &states, movements: &movements, deltaTime: 0.2)
        #expect(states[enemyID]?.mode == .idle)
        // May still ease through the current tile, but must not keep a long chase path.
        if let movement = movements[enemyID], movement.isMoving {
            #expect(movement.path.count == 2)
        }
    }

    @Test func reacquireCancelsForgetTimer() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 4, y: 1, story: 0)
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        var ai = EnemyAISystem(enemyConfig: enemyConfig)
        var states: [UUID: EnemyAIState] = [:]
        var movements: [UUID: MovementSystem] = [:]

        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: SimulationClock.tickDuration
        )

        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 0, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 1, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 2, story: 0)
        )

        ai.update(world: &world, states: &states, movements: &movements, deltaTime: 2.5)
        #expect(states[enemyID]?.mode == .searching)
        #expect(states[enemyID]?.forgetElapsed ?? 0 > 0)

        // Open LOS again.
        world.setTile(Tile(kind: .floor(isPit: false)), at: GridCoord(x: 2, y: 1, story: 0))
        ai.update(
            world: &world,
            states: &states,
            movements: &movements,
            deltaTime: SimulationClock.tickDuration
        )
        #expect(states[enemyID]?.mode == .chasing)
        #expect(states[enemyID]?.forgetElapsed == 0)
    }

    @Test func movesAtOneTilePerSecond() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 3, y: 1, story: 0)
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id
        let start = world.entity(id: enemyID)!.position

        var ai = EnemyAISystem(enemyConfig: enemyConfig)
        var states: [UUID: EnemyAIState] = [:]
        var movements: [UUID: MovementSystem] = [:]

        // One full second at 1 tile/s along a cardinal should commit onto the next tile.
        var elapsed: TimeInterval = 0
        while elapsed < 1.0 {
            ai.update(
                world: &world,
                states: &states,
                movements: &movements,
                deltaTime: SimulationClock.tickDuration
            )
            elapsed += SimulationClock.tickDuration
        }

        let end = world.entity(id: enemyID)!.position
        #expect(end != start)
        let chebyshev = max(abs(end.x - start.x), abs(end.y - start.y))
        #expect(chebyshev == 1)
        #expect(movements[enemyID]?.tilesPerSecond == 1.0)
    }

    @Test func contactEmitsEnemyIDAndRemovalClearsEntity() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 2, y: 1, story: 0),
            enemyAt: GridCoord(x: 2, y: 1, story: 0)
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        var loop = SimulationLoop(enemyConfig: enemyConfig)
        var movement = MovementSystem()
        var pending = PendingInput()

        let result = loop.tick(
            world: &world,
            movement: &movement,
            pendingInput: &pending,
            tickCount: 1
        )
        #expect(result.enemyContactID == enemyID)

        loop.removeEnemy(id: enemyID, from: &world)
        #expect(world.entity(id: enemyID) == nil)
        #expect(world.entities.contains(where: \.isEnemy) == false)
        #expect(world.enemyInContactWithPlayer() == nil)
    }
}
