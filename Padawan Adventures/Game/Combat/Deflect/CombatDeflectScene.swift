import QuartzCore
import SpriteKit
import UIKit

protocol CombatDeflectSceneDelegate: AnyObject {
    func combatDeflectSceneDidUpdateHealth(_ health: Int)
    func combatDeflectSceneDidUpdateMonsterHP(_ hp: Int, of total: Int)
    func combatDeflectSceneDidWin(starsAwarded: Int)
    func combatDeflectSceneDidLose()
}

/// SpriteKit deflect arena: the monster lobs one masked-word orb at a time and the player
/// taps the ring whose grapheme matches the word's first or last grapheme (per config) to
/// send it back. Tapping the orb itself replays the word.
final class CombatDeflectScene: MinigameScene {
    /// A live orb and the quadratic path it is currently following.
    struct OrbVisual {
        let id: UUID
        let letter: String
        let word: String
        /// Pronunciation track, replayed when the player taps the orb.
        let sfx: String
        /// The ring that deflects this orb. Updated when a wrong tap shuffles seats.
        var ring: CombatDeflectRing
        let travelSeconds: Double
        /// `CACurrentMediaTime()` when the inbound flight began.
        let flightStartedAt: TimeInterval
        let node: SKNode
        /// Unscaled projectile art width; the tap target is half this times `node.xScale`.
        let projectileWidth: CGFloat
        /// Pulsed on tap. `runFlight` rewrites the root node's scale every frame, so the
        /// feedback animation has to live on a child.
        let wordNode: SKNode
        /// Inbound bezier, used to predict where the orb will be. Not rewritten by
        /// `playDeflect`, so only read it while the orb is unresolved.
        let pathStart: CGPoint
        let pathControl: CGPoint
        let pathEnd: CGPoint
    }

    weak var deflectDelegate: CombatDeflectSceneDelegate?

    let enemyType: EnemyTypeConfig
    let playerFx: SoundEffectTable
    let spriteLibrary: SpriteLibrary
    let combatSprite: SpriteConfig?
    let enemySprite: (id: String, config: SpriteConfig)?
    let projectileSprite: (id: String, config: SpriteConfig)?
    let wallHeight: CGFloat
    let isoSquash: CGFloat

    var engine: CombatDeflectMinigameEngine
    var playerNode: AnimatedSpriteNode?
    var enemyNode: AnimatedSpriteNode?
    var ringLayer = SKNode()
    var hpTrack: SKSpriteNode?
    var activeOrb: OrbVisual?
    var activeLoopTrackID: String?
    var cachedPlayerWidth: CGFloat?
    var lastWordReplayAt: TimeInterval = 0
    let wordReplayCooldownSeconds: TimeInterval = 0.35

    /// Peak flight scale (`runFlight` endScale on the inbound leg).
    static let peakOrbScale: CGFloat = 1.15
    /// Base size such that the projectile's peak on-screen width (at impact) is 75% of
    /// the player's visible sprite width.
    var orbBaseSize: CGFloat { max(measuredPlayerWidth * 0.75 / Self.peakOrbScale, 1) }
    /// Extra scale for the animated projectile clip relative to `orbBaseSize`.
    static let projectileSpriteScale: CGFloat = 1.38
    /// The word row is fitted into this fraction of the projectile art's width. The art
    /// is a blob rather than a clean circle, so this is the knob to tune if the word
    /// crowds the edge.
    static let orbWordFitFraction: CGFloat = 0.62 * 1.3
    /// Word font size as a fraction of `orbBaseSize`.
    static let orbWordFontFraction: CGFloat = 0.26 * 1.3 * 1.15
    /// Extra gap between the blank square and the nearest letter, as a fraction of
    /// blank width.
    static let orbBlankLetterGapFraction: CGFloat = 0.35
    /// A long word grows the orb, but its peak on-screen width is capped here.
    static let maxOrbWidthFraction: CGFloat = 0.6

    var orbWordFontSize: CGFloat { max(orbBaseSize * Self.orbWordFontFraction, 10) }
    /// Unscaled cap, so `peakOrbScale` at impact still respects `maxOrbWidthFraction`.
    var maxProjectileWidth: CGFloat {
        max(size.width * Self.maxOrbWidthFraction / Self.peakOrbScale, 1)
    }

    let ringLineWidth: CGFloat = 2
    let ringDashLengths: [CGFloat] = [10, 8]
    /// Indexed by the fight's initial left-to-right order (supports up to `maxRingCount`).
    let ringColors: [UIColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple,
    ]
    /// Color stays with the grapheme across shuffles and layout rebuilds.
    var ringColorByGrapheme: [String: UIColor] = [:]
    /// Fired when the orbit lands or `rebuildRings` snaps a mid-shuffle layout.
    var ringShuffleCompletion: (() -> Void)?
    /// Wrong-tap orbit. `SKAction.customAction` ignores `timingMode`; ease lives in geometry.
    static let ringShuffleDuration: TimeInterval = 0.45
    let interOrbDelaySeconds: TimeInterval = 0.6
    /// The deflected orb returns at double speed.
    let deflectSpeedMultiplier: Double = 2
    let minimumReturnSeconds: TimeInterval = 0.25
    /// True while a wrong-letter flash or ring shuffle is in flight; blocks further ring taps.
    var isWrongLetterFeedbackActive = false

    let playerCombatLibraryID = "player_combat"
    let playerSwingAnimationName = "swing"
    let playerFlashActionKey = "playerFlash"
    let enemyFlashActionKey = "enemyFlash"
    let orbFlightActionKey = "orbFlight"
    let nextOrbActionKey = "nextOrb"
    let deflectFlashActionKey = "deflectFlash"
    let orbWordPulseActionKey = "orbWordPulse"
    let orbWrongLetterActionKey = "orbWrongLetter"
    let ringShuffleActionKey = "ringShuffle"

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
        projectileSprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat,
        isoSquash: CGFloat,
        vocabularySampler: LevelVocabularySampler? = nil
    ) {
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.spriteLibrary = spriteLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.projectileSprite = projectileSprite
        self.wallHeight = max(wallHeight, 1)
        self.isoSquash = isoSquash
        self.engine = CombatDeflectMinigameEngine(
            config: .init(from: deflectConfig),
            startingHealth: startingHealth,
            sampler: vocabularySampler
        )
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        GameLogger.mark(
            .combat,
            """
            deflect arena didMove size=\(Int(size.width))x\(Int(size.height)) \
            hp=\(engine.config.monsterHP) \
            position=\(engine.config.letterPosition.rawValue) \
            letters=\(engine.graphemes.map(\.grapheme).joined())
            """
        )
        GameLogger.step(.combat, "deflect.buildArena") { buildArena() }
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
