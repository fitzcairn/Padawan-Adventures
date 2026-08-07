import CoreGraphics
import Testing
@testable import Padawan_Adventures

@MainActor
struct CombatDeflectOrbSizingTests {
    @Test func peakOrbWidthIsSeventyFivePercentOfPlayerWidth() throws {
        let enemies = try EnemyConfig.loadFromBundle()
        let enemyType = try #require(enemies.enemies.values.first)
        let scene = CombatDeflectScene(
            size: CGSize(width: 400, height: 300),
            deflectConfig: .fallback,
            enemyType: enemyType,
            playerFx: .empty,
            startingHealth: 3,
            spriteLibrary: SpriteLibrary(),
            combatSprite: nil,
            enemySprite: nil,
            projectileSprite: nil,
            wallHeight: 80,
            isoSquash: 0.6125
        )
        // Without a player texture, measuredPlayerWidth falls back to playerSpriteHeight.
        let expectedPeak = scene.measuredPlayerWidth * 0.75
        let actualPeak = scene.orbBaseSize * CombatDeflectScene.peakOrbScale
        #expect(abs(actualPeak - expectedPeak) < 0.001)
    }
}
