import CoreGraphics
import SwiftUI

/// Everything a combat arena needs from the world / session, gathered once so the
/// factory does not need a parameter per knob.
@MainActor
struct CombatPresentationContext {
    let enemyType: EnemyTypeConfig
    let healthCount: Int
    let playerFx: SoundEffectTable
    let hudConfig: HudConfig
    let graphemeSoundRepeatSeconds: Double
    let minDecoyCount: Int
    let maxDecoyCount: Int
    let graphemeCase: CombatGraphemeCase
    let slashMaxSeconds: Double
    let slashMaxScreenWidthFraction: Double
    let spriteLibrary: SpriteLibrary
    let letterSpriteSetLibrary: LetterSpriteSetLibrary
    let combatSprite: SpriteConfig?
    let enemySprite: (id: String, config: SpriteConfig)?
    let projectileSprite: (id: String, config: SpriteConfig)?
    let wallHeight: CGFloat
    /// Isometric ellipse squash (`tile_height / tile_width`) for the deflect rings.
    let isoSquash: CGFloat
}

enum CombatMinigameFactory {
    @MainActor @ViewBuilder
    static func makeView(
        config: CombatMinigameConfig,
        context: CombatPresentationContext,
        onFinished: @escaping (MinigameOutcome) -> Void
    ) -> some View {
        switch config {
        case .slash:
            EnemyMinigameView(
                enemyType: context.enemyType,
                healthCount: context.healthCount,
                playerFx: context.playerFx,
                hudConfig: context.hudConfig,
                graphemeSoundRepeatSeconds: context.graphemeSoundRepeatSeconds,
                minDecoyCount: context.minDecoyCount,
                maxDecoyCount: context.maxDecoyCount,
                graphemeCase: context.graphemeCase,
                slashMaxSeconds: context.slashMaxSeconds,
                slashMaxScreenWidthFraction: context.slashMaxScreenWidthFraction,
                spriteLibrary: context.spriteLibrary,
                letterSpriteSetLibrary: context.letterSpriteSetLibrary,
                combatSprite: context.combatSprite,
                enemySprite: context.enemySprite,
                wallHeight: context.wallHeight,
                onFinished: onFinished
            )
        case .deflect(let deflect):
            CombatDeflectMinigameView(
                deflectConfig: deflect,
                enemyType: context.enemyType,
                healthCount: context.healthCount,
                playerFx: context.playerFx,
                hudConfig: context.hudConfig,
                spriteLibrary: context.spriteLibrary,
                combatSprite: context.combatSprite,
                enemySprite: context.enemySprite,
                projectileSprite: context.projectileSprite,
                wallHeight: context.wallHeight,
                isoSquash: context.isoSquash,
                onFinished: onFinished
            )
        }
    }
}
