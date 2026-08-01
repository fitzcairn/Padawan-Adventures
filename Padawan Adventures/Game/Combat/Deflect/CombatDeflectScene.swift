import QuartzCore
import SpriteKit
import UIKit

protocol CombatDeflectSceneDelegate: AnyObject {
    func combatDeflectSceneDidUpdateHealth(_ health: Int)
    func combatDeflectSceneDidUpdateMonsterHP(_ hp: Int, of total: Int)
    func combatDeflectSceneDidWin(starsAwarded: Int)
    func combatDeflectSceneDidLose()
}

/// SpriteKit deflect arena: the monster lobs one lettered orb at a time and the player
/// taps the matching isometric ring to send it back.
final class CombatDeflectScene: MinigameScene {
    /// A live orb and the quadratic path it is currently following.
    struct OrbVisual {
        let id: UUID
        let letter: String
        /// The ring that deflects this orb.
        let ring: CombatDeflectRing
        let travelSeconds: Double
        /// `CACurrentMediaTime()` when the inbound flight began.
        let flightStartedAt: TimeInterval
        let node: SKNode
    }

    weak var deflectDelegate: CombatDeflectSceneDelegate?

    let enemyType: EnemyTypeConfig
    let playerFx: SoundEffectTable
    let spriteLibrary: SpriteLibrary
    let combatSprite: SpriteConfig?
    let enemySprite: (id: String, config: SpriteConfig)?
    let wallHeight: CGFloat
    let isoSquash: CGFloat

    var engine: CombatDeflectMinigameEngine
    var playerNode: AnimatedSpriteNode?
    var enemyNode: AnimatedSpriteNode?
    var ringLayer = SKNode()
    var hpTrack: SKSpriteNode?
    var hpFill: SKSpriteNode?
    var activeOrb: OrbVisual?
    var activeLoopTrackID: String?
    var cachedPlayerWidth: CGFloat?

    /// 20% larger than the slash arena's letter sprites (`103.68`).
    let orbBaseSize: CGFloat = 103.68 * 1.2
    let ringLineWidth: CGFloat = 2
    let ringDashLengths: [CGFloat] = [10, 8]
    let outerRingColor = UIColor.lightGray
    /// Indexed by `CombatDeflectRing.rawValue` — left to right.
    let ringColors: [UIColor] = [.systemRed, .systemYellow, .systemBlue]
    let interOrbDelaySeconds: TimeInterval = 0.6
    let wrongTapDashSeconds: TimeInterval = 0.25
    /// The deflected orb returns at double speed.
    let deflectSpeedMultiplier: Double = 2
    let minimumReturnSeconds: TimeInterval = 0.25

    let playerCombatLibraryID = "player_combat"
    let playerSwingAnimationName = "swing"
    let playerFlashActionKey = "playerFlash"
    let enemyFlashActionKey = "enemyFlash"
    let orbFlightActionKey = "orbFlight"
    let nextOrbActionKey = "nextOrb"

    enum Layer {
        static let sprites: CGFloat = 10
        static let rings: CGFloat = 15
        static let ringLetters: CGFloat = 16
        static let orb: CGFloat = 20
        static let hpBar: CGFloat = 30
        static let vfx: CGFloat = 40
    }

    init(
        size: CGSize,
        deflectConfig: CombatDeflectConfig,
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        spriteLibrary: SpriteLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat,
        isoSquash: CGFloat
    ) {
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.spriteLibrary = spriteLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.wallHeight = max(wallHeight, 1)
        self.isoSquash = isoSquash
        self.engine = CombatDeflectMinigameEngine(
            config: .init(from: deflectConfig),
            startingHealth: startingHealth
        )
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        GameLogger.mark(
            .combat,
            """
            deflect arena didMove size=\(Int(size.width))x\(Int(size.height)) \
            hp=\(engine.config.monsterHP) \
            letters=\(engine.config.letters.map(\.letter).joined())
            """
        )
        GameLogger.step(.combat, "deflect.buildArena") { buildArena() }
        engine.begin()
        // Enable before combat FX so hum sits under letter cues; music −20%.
        SoundEffectsController.shared.setCombatMixActive(true)
        BackgroundMusicController.shared.setCombatMixActive(true)
        SoundEffectsController.shared.play(event: "combat_start", from: playerFx)
        activeLoopTrackID = SoundEffectsController.shared.startLoop(
            event: "combat_loop",
            from: playerFx
        )
        deflectDelegate?.combatDeflectSceneDidUpdateMonsterHP(
            engine.monsterHP,
            of: engine.config.monsterHP
        )
        scheduleNextOrb()
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.combat, "deflect.willMove teardown")
        stopCombatLoop()
        clearCombatMix()
    }

    override func rebuildLayout() {
        // SpriteKit can resize the scene while `buildArena` is still running,
        // before the nodes exist; the build finishes with the current size.
        guard let playerNode else { return }
        // Keep the fight running; only re-layout. A live orb keeps its baked path.
        playerNode.fitHeight(playerSpriteHeight)
        playerNode.position = playerPosition
        cachedPlayerWidth = nil
        placeEnemyAtTopOfView()
        rebuildRings()
        layoutMonsterHPBar()
    }
}
