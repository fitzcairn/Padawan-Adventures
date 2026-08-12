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
    /// Cumulative vocab used to sample slash targets without replacement.
    let vocabulary: LevelVocabularyPool
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
                vocabulary: context.vocabulary,
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

    @MainActor @ViewBuilder
    static func makeDemoView(
        config: CombatMinigameConfig,
        context: CombatPresentationContext,
        leadInSeconds: TimeInterval
    ) -> some View {
        switch config {
        case .slash:
            MinigameDemoView(
                make: { size in
                    CombatScene(
                        size: size,
                        enemyType: context.enemyType,
                        playerFx: context.playerFx,
                        startingHealth: context.healthCount,
                        graphemeSoundRepeatSeconds: context.graphemeSoundRepeatSeconds,
                        minDecoyCount: context.minDecoyCount,
                        maxDecoyCount: context.maxDecoyCount,
                        graphemeCase: context.graphemeCase,
                        vocabulary: context.vocabulary,
                        slashMaxSeconds: context.slashMaxSeconds,
                        slashMaxScreenWidthFraction: context.slashMaxScreenWidthFraction,
                        spriteLibrary: context.spriteLibrary,
                        letterSpriteSetLibrary: context.letterSpriteSetLibrary,
                        combatSprite: context.combatSprite,
                        enemySprite: context.enemySprite,
                        wallHeight: context.wallHeight
                    )
                },
                timing: .init(maxCorrectMoves: 3),
                leadInSeconds: leadInSeconds
            )
        case .deflect(let deflect):
            // The tutorial demonstrates a single deflect, so the HP bar has to empty
            // on that hit for the coin to make sense.
            let demoConfig: CombatDeflectConfig = {
                var config = deflect
                config.monsterHP = 1
                return config
            }()
            MinigameDemoView(
                make: { size in
                    CombatDeflectScene(
                        size: size,
                        deflectConfig: demoConfig,
                        enemyType: context.enemyType,
                        playerFx: context.playerFx,
                        // An untapped orb still costs a heart; keep headroom so the
                        // demo can never end in a loss.
                        startingHealth: max(context.healthCount, 3),
                        spriteLibrary: context.spriteLibrary,
                        combatSprite: context.combatSprite,
                        enemySprite: context.enemySprite,
                        projectileSprite: context.projectileSprite,
                        wallHeight: context.wallHeight,
                        isoSquash: context.isoSquash
                    )
                },
                timing: .init(maxCorrectMoves: 3),
                leadInSeconds: leadInSeconds
            )
        }
    }
}
