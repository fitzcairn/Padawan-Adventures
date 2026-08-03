import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct CombatSlashReuseTests {
    @Test func slashContainerIsReusedAcrossUpdates() throws {
        let enemies = try EnemyConfig.loadFromBundle()
        let enemyType = try #require(enemies.enemies.values.first)
        let spriteID = try #require(enemyType.sprite)
        let enemySpriteConfig = try #require(enemies.sprites[spriteID])
        let enemySprite: (id: String, config: SpriteConfig)? = (spriteID, enemySpriteConfig)
        let scene = CombatScene(
            size: CGSize(width: 400, height: 300),
            enemyType: enemyType,
            playerFx: .empty,
            startingHealth: 3,
            spriteLibrary: SpriteLibrary(),
            letterSpriteSetLibrary: LetterSpriteSetLibrary(),
            combatSprite: nil,
            enemySprite: enemySprite,
            wallHeight: 80
        )

        var points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
        ]
        scene.updateSlashLineForTesting(points: points)
        #expect(scene.slashContainerBuildCount == 1)

        for i in 2...10 {
            points.append(CGPoint(x: CGFloat(i * 10), y: 0))
            scene.updateSlashLineForTesting(points: points)
        }
        #expect(scene.slashContainerBuildCount == 1)

        scene.clearSlashLine()
        scene.updateSlashLineForTesting(points: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 30, y: 20),
        ])
        #expect(scene.slashContainerBuildCount == 2)
    }
}
