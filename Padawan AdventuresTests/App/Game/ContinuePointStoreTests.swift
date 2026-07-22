import Foundation
import Testing
@testable import Padawan_Adventures

struct ContinuePointStoreTests {
    @Test func seedsWithInitialWorld() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.healthCount = 3
        world.energyCount = 2
        let store = ContinuePointStore(world: world)
        #expect(store.snapshot.healthCount == 3)
        #expect(store.snapshot.energyCount == 2)
        #expect(store.snapshot.playerPosition == world.spawn)
    }

    @Test func captureIfSafeUpdatesOnSettleWithoutEncounter() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.energyCount = 2
        var store = ContinuePointStore(world: world)

        world.energyCount = 1
        world.setPlayerPosition(GridCoord(x: 1, y: 0, story: 0))
        var tick = SimulationTickResult()
        tick.shouldPersist = true
        store.captureIfSafe(world, tick: tick)

        #expect(store.snapshot.energyCount == 1)
        #expect(store.snapshot.playerPosition == GridCoord(x: 1, y: 0, story: 0))
    }

    @Test func captureIfSafeSkipsWhenEnemyContact() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.energyCount = 2
        var store = ContinuePointStore(world: world)
        let original = store.snapshot

        world.energyCount = 0
        world.setPlayerPosition(GridCoord(x: 2, y: 0, story: 0))
        var tick = SimulationTickResult()
        tick.shouldPersist = true
        tick.enemyContactID = UUID()
        store.captureIfSafe(world, tick: tick)

        #expect(store.snapshot.energyCount == original.energyCount)
        #expect(store.snapshot.playerPosition == original.playerPosition)
        #expect(!tick.shouldPersistContinueSave)
    }

    @Test func shouldPersistContinueSaveOnlyWhenSafeSettle() {
        var safe = SimulationTickResult()
        safe.shouldPersist = true
        #expect(safe.shouldPersistContinueSave)

        var enemyContact = SimulationTickResult()
        enemyContact.shouldPersist = true
        enemyContact.enemyContactID = UUID()
        #expect(!enemyContact.shouldPersistContinueSave)

        var notSettled = SimulationTickResult()
        notSettled.shouldPersist = false
        #expect(!notSettled.shouldPersistContinueSave)
    }

    @Test func captureIfSafeSkipsWhenPitContact() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.healthCount = 1
        var store = ContinuePointStore(world: world)
        let original = store.snapshot

        world.healthCount = 0
        world.setPlayerPosition(GridCoord(x: 1, y: 1, story: 0))
        var tick = SimulationTickResult()
        tick.shouldPersist = true
        tick.didEnterPit = true
        store.captureIfSafe(world, tick: tick)

        #expect(store.snapshot.healthCount == original.healthCount)
        #expect(store.snapshot.playerPosition == original.playerPosition)
    }

    @Test func captureIfSafeSkipsWhenNotPersisting() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        var store = ContinuePointStore(world: world)
        let originalPosition = store.snapshot.playerPosition

        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))
        var tick = SimulationTickResult()
        tick.shouldPersist = false
        store.captureIfSafe(world, tick: tick)

        #expect(store.snapshot.playerPosition == originalPosition)
    }

    @Test func explicitCaptureUpdatesWhenProgressable() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        var store = ContinuePointStore(world: world)

        world.healthCount = 0
        world.setPlayerPosition(GridCoord(x: 1, y: 1, story: 0))
        store.capture(world)

        #expect(store.snapshot.healthCount == 0)
        #expect(store.snapshot.playerPosition == GridCoord(x: 1, y: 1, story: 0))
    }

    @Test func captureSkipsZeroEnergyWithVisibleEnemy() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 0, story: 0),
            enemyAt: GridCoord(x: 1, y: 0, story: 0)
        )
        world.energyCount = 2
        var store = ContinuePointStore(world: world)
        let original = store.snapshot

        world.energyCount = 0
        store.capture(world)

        #expect(store.snapshot.energyCount == original.energyCount)
        #expect(ContinuePointStore.isProgressable(world) == false)
    }

    @Test func captureIfSafeSkipsZeroEnergyWithVisibleEnemy() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 2, y: 1, story: 0)
        )
        world.energyCount = 1
        var store = ContinuePointStore(world: world)
        let original = store.snapshot

        world.energyCount = 0
        world.setPlayerPosition(GridCoord(x: 1, y: 1, story: 0))
        var tick = SimulationTickResult()
        tick.shouldPersist = true
        store.captureIfSafe(world, tick: tick)

        #expect(store.snapshot.energyCount == original.energyCount)
        #expect(store.snapshot.playerPosition == original.playerPosition)
    }

    @Test func captureAllowsZeroEnergyWhenEnemyHasNoLineOfSight() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 1, story: 0),
            enemyAt: GridCoord(x: 2, y: 1, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false)),
            at: GridCoord(x: 1, y: 0, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false)),
            at: GridCoord(x: 1, y: 1, story: 0)
        )
        world.setTile(
            Tile(kind: .wall(destructible: false)),
            at: GridCoord(x: 1, y: 2, story: 0)
        )
        world.energyCount = 0
        var store = ContinuePointStore(world: world)

        world.setPlayerPosition(GridCoord(x: 0, y: 0, story: 0))
        store.capture(world)

        #expect(store.snapshot.energyCount == 0)
        #expect(store.snapshot.playerPosition == GridCoord(x: 0, y: 0, story: 0))
        #expect(ContinuePointStore.isProgressable(world))
    }

    @Test func captureAllowsZeroEnergyWithNoEnemies() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        world.energyCount = 2
        var store = ContinuePointStore(world: world)

        world.energyCount = 0
        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))
        store.capture(world)

        #expect(store.snapshot.energyCount == 0)
        #expect(store.snapshot.playerPosition == GridCoord(x: 2, y: 2, story: 0))
    }

    private func worldWithEnemy(
        playerAt: GridCoord,
        enemyAt: GridCoord,
        width: Int = 3,
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
        return GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: [world.entities[0], enemy],
            spawn: world.spawn
        )
    }
}

struct DefeatRulesTests {
    @Test func enemyDefeatWhenEnergyIsZero() {
        #expect(DefeatRules.isDefeatedByEnemy(energy: 0))
        #expect(!DefeatRules.isDefeatedByEnemy(energy: 1))
        #expect(!DefeatRules.isDefeatedByEnemy(energy: 2))
    }

    @Test func pitDefeatWhenHealthIsZero() {
        #expect(DefeatRules.isDefeatedByPit(health: 0))
        #expect(!DefeatRules.isDefeatedByPit(health: 1))
        #expect(!DefeatRules.isDefeatedByPit(health: 3))
    }

    @Test func restoredVitalFloorsZeroToOne() {
        #expect(DefeatRules.restoredVital(0) == 1)
        #expect(DefeatRules.restoredVital(1) == 1)
        #expect(DefeatRules.restoredVital(3) == 3)
    }
}
