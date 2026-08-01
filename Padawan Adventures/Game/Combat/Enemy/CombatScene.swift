import QuartzCore
import SpriteKit
import UIKit

protocol CombatSceneDelegate: AnyObject {
    func combatSceneDidUpdateStars(_ stars: Int)
    func combatSceneDidUpdateHealth(_ health: Int)
    func combatSceneDidWin(starsAwarded: Int)
    func combatSceneDidLose()
}

/// SpriteKit combat arena: player/enemy sprites, curved shots, slash input, VFX.
final class CombatScene: MinigameScene {
    struct ShotVisual {
        /// Current quadratic path (may be retargeted when the cue changes).
        var pathStart: CGPoint
        var pathControl: CGPoint
        var pathEnd: CGPoint
        var pathSpawnElapsed: Double
        var pathTravelSeconds: Double
        /// Original flight clock — used so scale keeps growing even after a retarget.
        let scaleSpawnElapsed: Double
        let scaleTravelSeconds: Double
        /// Live: matching the current phonetic cue. Updated when the cue changes.
        var canHitPlayer: Bool
        let visualLetter: String
        let node: SKNode
    }

    weak var combatDelegate: CombatSceneDelegate?

    let enemyType: EnemyTypeConfig
    let playerFx: SoundEffectTable
    let slashMaxSeconds: Double
    let slashMaxScreenWidthFraction: Double
    let spriteLibrary: SpriteLibrary
    let letterSpriteSetLibrary: LetterSpriteSetLibrary
    let combatSprite: SpriteConfig?
    let enemySprite: (id: String, config: SpriteConfig)?
    let wallHeight: CGFloat

    var engine: CombatMinigameEngine
    var playerNode: AnimatedSpriteNode?
    var enemyNode: AnimatedSpriteNode?
    var shotVisuals: [UUID: ShotVisual] = [:]
    var slashPoints: [CGPoint] = []
    var slashPathLength: CGFloat = 0
    var slashLine: SKNode?
    var slashStrokes: [SKShapeNode] = []
    /// Test seam: how many times the slash container has been built, to prove it is
    /// reused across a drag rather than rebuilt per touch event.
    var slashContainerBuildCount = 0
    var slashStartedAt: TimeInterval?
    var isSlashActive = false
    var lastUpdateTime: TimeInterval?
    var activeLoopTrackID: String?

    let shotBaseSize: CGFloat = 103.68
    let playerFlashActionKey = "playerFlash"
    let playerCombatLibraryID = "player_combat"
    let playerSwingAnimationName = "swing"
    let slashFadeOutSeconds: TimeInterval = 0.28

    init(
        size: CGSize,
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        letterSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultLetterSoundRepeatSeconds,
        letterSpawnRate: Double = CombatMinigameEngine.Config.defaultLetterSpawnRate,
        letterCase: CombatLetterCase = .upper,
        slashMaxSeconds: Double = EnemyConfig.fallbackSlashMaxSeconds,
        slashMaxScreenWidthFraction: Double = EnemyConfig.fallbackSlashMaxScreenWidthFraction,
        spriteLibrary: SpriteLibrary,
        letterSpriteSetLibrary: LetterSpriteSetLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat
    ) {
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.slashMaxSeconds = max(slashMaxSeconds, 0.05)
        self.slashMaxScreenWidthFraction = min(max(slashMaxScreenWidthFraction, 0.01), 1)
        self.spriteLibrary = spriteLibrary
        self.letterSpriteSetLibrary = letterSpriteSetLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.wallHeight = max(wallHeight, 1)
        self.engine = CombatMinigameEngine(
            config: .init(
                from: enemyType,
                letterSoundRepeatSeconds: letterSoundRepeatSeconds,
                letterSpawnRate: letterSpawnRate,
                letterCase: letterCase
            ),
            startingHealth: startingHealth
        )
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        GameLogger.step(.combat, "combat.buildArena") { buildArena() }
        engine.begin()
        // Enable before combat FX so hum/slash sit under letter cues; music −20%.
        SoundEffectsController.shared.setCombatMixActive(true)
        BackgroundMusicController.shared.setCombatMixActive(true)
        SoundEffectsController.shared.play(event: "combat_start", from: playerFx)
        activeLoopTrackID = SoundEffectsController.shared.startLoop(
            event: "combat_loop",
            from: playerFx
        )
        combatDelegate?.combatSceneDidUpdateStars(0)
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.combat, "combat.willMove teardown")
        stopCombatLoop()
        clearCombatMix()
    }

    override func rebuildLayout() {
        // Keep the fight running; only re-layout sprites. Live shots keep their paths.
        repositionArenaNodes()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !didEnd else { return }

        // Use CACurrentMediaTime — same clock as touch handlers (not SKScene currentTime).
        if isSlashActive, hasSlashTimedOut(at: CACurrentMediaTime()) {
            endSlash()
        }

        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime

        let events = engine.tick(dt: dt)
        for event in events {
            handle(event)
        }
        syncShotAiming()
        syncShotMotion()
        checkImpacts()
    }
}
