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
    enum ShotRole {
        case inbound
        /// Correct slash: flying back at the enemy on an accelerated arc.
        case returning
        case sweepingOff
        case charging
    }

    struct ShotVisual {
        var pathStart: CGPoint
        var pathControl1: CGPoint
        var pathControl2: CGPoint
        var pathEnd: CGPoint
        /// Scene-clock stamp when this (re)targeting began.
        var pathStartedAt: Double
        var pathDurationSeconds: Double
        let scaleStartedAt: Double
        let scaleDurationSeconds: Double
        let letter: String
        let isTarget: Bool
        var role: ShotRole
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
    /// In-scene monster HP / damage bar (same chrome as the deflect arenas).
    var hpTrack: SKSpriteNode?
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

    /// Sprite motion clock. Independent of the engine so the resolution choreography
    /// keeps animating after the wave outcome is decided and the engine freezes.
    var sceneElapsed: Double = 0
    /// Sprites still finishing their resolution animation; at zero the wave is done.
    var resolvingSpriteCount = 0
    /// One damage sound + player flash per failed wave, however many sprites land.
    var didPlayWaveDamageSound = false

    let shotBaseSize: CGFloat = 103.68
    let playerFlashActionKey = "playerFlash"
    let playerCombatLibraryID = "player_combat"
    let playerSwingAnimationName = "swing"
    let slashFadeOutSeconds: TimeInterval = 0.28

    static let sweepOffSeconds: Double = 0.35
    /// Return flight is this many times faster than the remaining inbound travel time.
    static let returnSpeedMultiplier: Double = 2.5
    static let returnSecondsRange: ClosedRange<Double> = 0.18...0.4
    /// Charge duration for a sprite a full screen height away; scaled by distance and clamped.
    static let chargeReferenceSeconds: Double = 0.5
    static let chargeSecondsRange: ClosedRange<Double> = 0.25...0.5

    enum Layer {
        static let sprites: CGFloat = 10
        static let shots: CGFloat = 20
        static let hpBar: CGFloat = 30
        static let vfx: CGFloat = 40
    }

    init(
        size: CGSize,
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        graphemeSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultGraphemeSoundRepeatSeconds,
        minDecoyCount: Int = CombatMinigameEngine.Config.defaultMinDecoyCount,
        maxDecoyCount: Int = CombatMinigameEngine.Config.defaultMaxDecoyCount,
        graphemeCase: CombatGraphemeCase = .upper,
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
                graphemeSoundRepeatSeconds: graphemeSoundRepeatSeconds,
                minDecoyCount: minDecoyCount,
                maxDecoyCount: maxDecoyCount,
                graphemeCase: graphemeCase
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
        layoutMonsterHPBar()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !didEnd else { return }

        // Use CACurrentMediaTime — same clock as touch handlers (not SKScene currentTime).
        if isSlashActive, hasSlashTimedOut(at: CACurrentMediaTime()) {
            endSlash()
        }

        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime
        sceneElapsed += dt

        for event in engine.tick(dt: dt) {
            handle(event)
        }
        syncShotMotion()
        checkImpacts()
    }
}
