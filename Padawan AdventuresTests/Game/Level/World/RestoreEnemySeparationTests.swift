import Foundation
import Testing
@testable import Padawan_Adventures

struct RestoreEnemySeparationTests {
    @Test func movesEnemyWithinTwoTilesFourAway() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 4, y: 4, story: 0),
            enemyAt: GridCoord(x: 5, y: 4, story: 0),
            width: 12,
            height: 12
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        let moved = world.separateNearbyEnemiesOnRestore()
        let enemy = world.entity(id: enemyID)

        #expect(moved == 1)
        #expect(enemy?.position != GridCoord(x: 5, y: 4, story: 0))
        if let player = world.playerPosition, let enemyPosition = enemy?.position {
            let distance = abs(enemyPosition.x - player.x) + abs(enemyPosition.y - player.y)
            #expect(distance == 4)
        }
    }

    @Test func leavesDistantEnemyInPlace() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 0, y: 0, story: 0),
            enemyAt: GridCoord(x: 5, y: 0, story: 0),
            width: 10,
            height: 3
        )
        let original = world.entities.first(where: \.isEnemy)!.position

        let moved = world.separateNearbyEnemiesOnRestore()

        #expect(moved == 0)
        #expect(world.entities.first(where: \.isEnemy)?.position == original)
    }

    @Test func movesEnemyAtExactlyTwoTiles() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 3, y: 3, story: 0),
            enemyAt: GridCoord(x: 5, y: 3, story: 0),
            width: 10,
            height: 10
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        let moved = world.separateNearbyEnemiesOnRestore()

        #expect(moved == 1)
        if let player = world.playerPosition,
           let enemyPosition = world.entity(id: enemyID)?.position {
            let distance = abs(enemyPosition.x - player.x) + abs(enemyPosition.y - player.y)
            #expect(distance == 4)
        }
    }

    @Test func prefersCardinalSeparationTile() {
        var world = worldWithEnemy(
            playerAt: GridCoord(x: 4, y: 4, story: 0),
            enemyAt: GridCoord(x: 4, y: 5, story: 0),
            width: 12,
            height: 12
        )
        let enemyID = world.entities.first(where: \.isEnemy)!.id

        _ = world.separateNearbyEnemiesOnRestore()

        // Deterministic cardinal preference: first free ring tile in sort order is (0, -4).
        #expect(world.entity(id: enemyID)?.position == GridCoord(x: 4, y: 0, story: 0))
    }

    private func worldWithEnemy(
        playerAt: GridCoord,
        enemyAt: GridCoord,
        width: Int,
        height: Int
    ) -> GameWorld {
        var world = TestWorldFactory.emptyFloor(width: width, height: height)
        world.setPlayerPosition(playerAt)
        let enemy = GameEntity(
            letter: "E",
            position: enemyAt,
            isPlayer: false,
            enemyTypeID: "spider"
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
