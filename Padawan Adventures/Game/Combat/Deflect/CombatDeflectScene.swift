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
    private struct OrbVisual {
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

    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable
    private let spriteLibrary: SpriteLibrary
    private let combatSprite: SpriteConfig?
    private let enemySprite: (id: String, config: SpriteConfig)?
    private let wallHeight: CGFloat
    private let isoSquash: CGFloat

    private var engine: CombatDeflectMinigameEngine
    private var playerNode: AnimatedSpriteNode?
    private var enemyNode: AnimatedSpriteNode?
    private var ringLayer = SKNode()
    private var hpTrack: SKSpriteNode?
    private var hpFill: SKSpriteNode?
    private var activeOrb: OrbVisual?
    private var activeLoopTrackID: String?
    private var cachedPlayerWidth: CGFloat?

    /// 20% larger than the slash arena's letter sprites (`103.68`).
    private let orbBaseSize: CGFloat = 103.68 * 1.2
    private let ringLineWidth: CGFloat = 2
    private let ringDashLengths: [CGFloat] = [10, 8]
    private let outerRingColor = UIColor.lightGray
    /// Indexed by `CombatDeflectRing.rawValue` — left to right.
    private let ringColors: [UIColor] = [.systemRed, .systemYellow, .systemBlue]
    private let interOrbDelaySeconds: TimeInterval = 0.6
    private let wrongTapDashSeconds: TimeInterval = 0.25
    /// The deflected orb returns at double speed.
    private let deflectSpeedMultiplier: Double = 2
    private let minimumReturnSeconds: TimeInterval = 0.25

    private let playerCombatLibraryID = "player_combat"
    private let playerSwingAnimationName = "swing"
    private let playerFlashActionKey = "playerFlash"
    private let enemyFlashActionKey = "enemyFlash"
    private let orbFlightActionKey = "orbFlight"
    private let nextOrbActionKey = "nextOrb"

    private enum Layer {
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

    // MARK: - Layout

    /// 40% screen height × 1.2 (20% larger) — same as the slash arena.
    private var playerSpriteHeight: CGFloat { size.height * 0.48 }

    /// 2× world height, then −30% (`2 × 0.7 × wallHeight × scale`).
    private var enemySpriteHeight: CGFloat {
        guard let enemySprite else { return size.height * 0.084 }
        return 1.4 * wallHeight * CGFloat(enemySprite.config.scale)
    }

    /// Feet (sprite bottom-middle) sit on the view's bottom-middle.
    private var playerPosition: CGPoint {
        CGPoint(x: size.width * 0.5, y: 0)
    }

    private func buildArena() {
        playerNode?.removeFromParent()
        enemyNode?.removeFromParent()

        let player = AnimatedSpriteNode(
            size: CGSize(width: playerSpriteHeight, height: playerSpriteHeight)
        )
        player.fitHeight(playerSpriteHeight)
        player.zPosition = Layer.sprites
        player.name = "player"
        addChild(player)
        playerNode = player
        // `show` applies the V-inversion scale so feet stay at position and the
        // body extends upward onto the screen (raw texture assignment does not).
        if combatSprite != nil {
            player.show(
                name: playerSwingAnimationName,
                library: spriteLibrary,
                libraryID: playerCombatLibraryID
            )
            player.fitHeight(playerSpriteHeight)
        }
        player.position = playerPosition
        cachedPlayerWidth = nil

        let enemy = AnimatedSpriteNode(
            size: CGSize(width: enemySpriteHeight, height: enemySpriteHeight)
        )
        enemy.zPosition = Layer.sprites
        enemy.name = "enemy"
        addChild(enemy)
        enemyNode = enemy
        if let enemySprite,
           spriteLibrary.animation(id: enemySprite.id, named: "idle_down") != nil {
            enemy.play(
                name: "idle_down",
                library: spriteLibrary,
                libraryID: enemySprite.id
            )
        }
        // Size + place after texture is known so the top-middle pixel sits on the view top.
        placeEnemyAtTopOfView()

        ringLayer.removeFromParent()
        ringLayer = SKNode()
        addChild(ringLayer)
        // Rings need the fitted player texture to measure its visible width.
        rebuildRings()
        buildMonsterHPBar()
    }

    private func placeEnemyAtTopOfView() {
        guard let enemyNode else { return }
        pinToTopOfView(enemyNode, height: enemySpriteHeight)
    }

    /// Geometry is derived fresh so it always matches the current scene size and
    /// the fitted player sprite.
    private var geometry: CombatDeflectGeometry {
        CombatDeflectGeometry(
            sceneSize: size,
            squash: isoSquash,
            playerSpriteWidth: measuredPlayerWidth
        )
    }

    /// Measuring opaque width scans the texture's pixels, so it is cached until the
    /// player sprite is refitted (`geometry` is read on every touch).
    private var measuredPlayerWidth: CGFloat {
        if let cachedPlayerWidth { return cachedPlayerWidth }
        guard let playerNode else { return playerSpriteHeight }
        let width = opaqueContentWidthPoints(for: playerNode)
        cachedPlayerWidth = width
        return width
    }

    // MARK: - Rings

    private func rebuildRings() {
        ringLayer.removeAllChildren()
        let geo = geometry

        // Outer ring: centered on the player, so its lower half sits off-screen by design.
        let outer = makeDashedEllipse(rect: geo.outerRect, color: outerRingColor)
        ringLayer.addChild(outer)

        for ring in CombatDeflectRing.allCases {
            let color = ringColor(for: ring)
            let ellipse = makeDashedEllipse(rect: geo.ringRect(ring), color: color)
            ringLayer.addChild(ellipse)

            guard let letter = letter(for: ring) else { continue }
            let label = makeOutlinedLetter(
                letter,
                fontSize: max(geo.ringRadii.height * 1.6, 18),
                outline: color
            )
            label.position = geo.ringLabelPosition(ring)
            label.zPosition = Layer.ringLetters
            ringLayer.addChild(label)
        }
    }

    private func ringColor(for ring: CombatDeflectRing) -> UIColor {
        guard ring.rawValue < ringColors.count else { return .white }
        return ringColors[ring.rawValue]
    }

    private func letter(for ring: CombatDeflectRing) -> String? {
        let letters = engine.config.letters
        guard ring.rawValue < letters.count else { return nil }
        return letters[ring.rawValue].letter
    }

    /// `SKShapeNode` has no dash property, so the dashes are baked into the path.
    private func makeDashedEllipse(rect: CGRect, color: UIColor) -> SKShapeNode {
        let base = CGPath(ellipseIn: rect, transform: nil)
        let dashed = base.copy(dashingWithPhase: 0, lengths: ringDashLengths)
        let node = SKShapeNode(path: dashed)
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = ringLineWidth
        node.isAntialiased = true
        node.zPosition = Layer.rings
        return node
    }

    /// `SKLabelNode` cannot stroke text, so outlined letters need `attributedText`.
    /// A negative `strokeWidth` fills *and* strokes; positive would give hollow text.
    private func makeOutlinedLetter(
        _ text: String,
        fontSize: CGFloat,
        outline: UIColor
    ) -> SKLabelNode {
        let font = UIFont(name: AppFont.name, size: fontSize)
            ?? UIFont.boldSystemFont(ofSize: fontSize)
        let label = SKLabelNode(attributedText: NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: font,
                .foregroundColor: UIColor.white,
                .strokeColor: outline,
                .strokeWidth: -6.0,
            ]
        ))
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    // MARK: - Monster HP bar

    private func buildMonsterHPBar() {
        hpTrack?.removeFromParent()

        let track = SKSpriteNode(color: UIColor.white.withAlphaComponent(0.22), size: .zero)
        track.anchorPoint = CGPoint(x: 0, y: 0.5)
        track.zPosition = Layer.hpBar
        track.name = "monsterHP"
        addChild(track)
        hpTrack = track

        let fill = SKSpriteNode(color: CombatHUDView.color(forProgress: 1), size: .zero)
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.zPosition = 1
        track.addChild(fill)
        hpFill = fill

        layoutMonsterHPBar()
    }

    /// Sits directly to the right of the monster, vertically centered on it.
    private func layoutMonsterHPBar() {
        guard let hpTrack, let hpFill, let enemyNode else { return }
        let frame = enemyNode.calculateAccumulatedFrame()
        let width = size.width * 0.18
        let height: CGFloat = 18
        hpTrack.size = CGSize(width: width, height: height)
        hpTrack.position = CGPoint(x: frame.maxX + 12, y: frame.midY)
        hpFill.position = .zero
        hpFill.size = CGSize(width: width * monsterHPFraction, height: height)
        hpFill.color = CombatHUDView.color(forProgress: monsterHPFraction)
    }

    private var monsterHPFraction: CGFloat {
        let total = max(engine.config.monsterHP, 1)
        return min(max(CGFloat(engine.monsterHP) / CGFloat(total), 0), 1)
    }

    /// Full and green at the start, draining toward red as the monster is worn down.
    private func animateMonsterHPBar() {
        guard let hpTrack, let hpFill else { return }
        let fraction = monsterHPFraction
        hpFill.run(.resize(toWidth: hpTrack.size.width * fraction, duration: 0.22))
        hpFill.color = CombatHUDView.color(forProgress: fraction)
    }

    // MARK: - Engine events

    private func handle(_ events: [CombatDeflectEvent]) {
        for event in events {
            switch event {
            case let .throwOrb(id, letter, ring, travelSeconds):
                throwOrb(id: id, letter: letter, ring: ring, travelSeconds: travelSeconds)
            case let .speakLetter(trackID):
                // Phonetic tracks duck music + ambience loops for the clip's duration.
                SoundEffectsController.shared.play(trackID: trackID)
            case let .monsterHealthChanged(hp):
                animateMonsterHPBar()
                deflectDelegate?.combatDeflectSceneDidUpdateMonsterHP(
                    hp,
                    of: engine.config.monsterHP
                )
            case let .playerHealthChanged(health):
                deflectDelegate?.combatDeflectSceneDidUpdateHealth(health)
            case let .won(starsAwarded):
                finishWin(starsAwarded: starsAwarded)
            case .lost:
                finishLose()
            }
        }
    }

    /// Runs after a resolved orb when the fight is still going.
    private func scheduleNextOrb() {
        guard !didEnd, engine.outcome == nil else { return }
        removeAction(forKey: nextOrbActionKey)
        run(
            .sequence([
                .wait(forDuration: interOrbDelaySeconds),
                .run { [weak self] in
                    guard let self else { return }
                    self.handle(self.engine.throwNextOrb())
                },
            ]),
            withKey: nextOrbActionKey
        )
    }

    // MARK: - Orbs

    private func throwOrb(
        id: UUID,
        letter: String,
        ring: CombatDeflectRing,
        travelSeconds: Double
    ) {
        guard let playerNode, let enemyNode else { return }
        let travel = max(travelSeconds, 0.2)
        // A previous deflect may have left the player mirrored.
        setPlayerFacingLeft(false)
        let start = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let end = bodyCenter(of: playerNode, height: playerSpriteHeight)
        let control = inboundControlPoint(from: start, to: end)

        let node = makeOrbNode(letter: letter)
        node.position = start
        node.setScale(0.35)
        node.zPosition = Layer.orb
        node.name = "orb-\(id.uuidString)"
        addChild(node)

        activeOrb = OrbVisual(
            id: id,
            letter: letter,
            ring: ring,
            travelSeconds: travel,
            flightStartedAt: CACurrentMediaTime(),
            node: node
        )

        runFlight(
            on: node,
            start: start,
            control: control,
            end: end,
            duration: travel,
            startScale: 0.35,
            endScale: 1.15
        ) { [weak self] in
            // Reached the player untapped — same consequence as a wrong tap.
            self?.resolvePlayerHit()
        }
    }

    /// Grey circle with the letter on it. Placeholder art until real orb sprites land.
    private func makeOrbNode(letter: String) -> SKNode {
        let circle = SKShapeNode(circleOfRadius: orbBaseSize * 0.5)
        circle.fillColor = UIColor.lightGray.withAlphaComponent(0.95)
        circle.strokeColor = .white
        circle.lineWidth = 2
        circle.isAntialiased = true

        let label = makeOutlinedLetter(
            letter,
            fontSize: orbBaseSize * 0.55,
            outline: .darkGray
        )
        label.zPosition = 1
        circle.addChild(label)
        return circle
    }

    private func inboundControlPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        let lateral = CGFloat.random(in: -size.width * 0.42...size.width * 0.42)
        return CGPoint(x: mid.x + lateral, y: mid.y)
    }

    /// Follows a quadratic path while scaling, then calls `completion`.
    private func runFlight(
        on node: SKNode,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        duration: TimeInterval,
        startScale: CGFloat,
        endScale: CGFloat,
        completion: @escaping () -> Void
    ) {
        let span = max(duration, 0.05)
        let follow = SKAction.customAction(withDuration: span) { [weak self] node, elapsed in
            guard let self else { return }
            let t = min(max(CGFloat(elapsed) / CGFloat(span), 0), 1)
            node.position = self.quadraticBezier(t: t, start: start, control: control, end: end)
            node.setScale(startScale + (endScale - startScale) * t)
        }
        node.run(
            .sequence([follow, .run(completion)]),
            withKey: orbFlightActionKey
        )
    }

    /// How far along its inbound flight the live orb is (`0…1`).
    private func inboundProgress(of orb: OrbVisual) -> Double {
        let elapsed = CACurrentMediaTime() - orb.flightStartedAt
        return min(max(elapsed / max(orb.travelSeconds, 0.05), 0), 1)
    }

    private func removeOrbNode() {
        activeOrb?.node.removeAllActions()
        activeOrb?.node.removeFromParent()
        activeOrb = nil
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, engine.outcome == nil else { return }
        guard let touch = touches.first else { return }
        guard let ring = geometry.hitTest(touch.location(in: self)) else { return }

        switch engine.registerTap(ring: ring) {
        case .ignored:
            break
        case .correct(let ring):
            playDeflect(ring: ring)
        case .wrong:
            playWrongTap()
        }
    }

    /// Swing toward the tapped ring, then send the orb home at double speed.
    private func playDeflect(ring: CombatDeflectRing) {
        guard let orb = activeOrb, let playerNode, let enemyNode else { return }
        SoundEffectsController.shared.play(event: "slash", from: playerFx)
        if combatSprite != nil {
            playerNode.playOnce(
                name: playerSwingAnimationName,
                library: spriteLibrary,
                libraryID: playerCombatLibraryID
            )
            // Only one swing clip exists, so mirror it for the left-hand ring.
            // (`playOnce` resets scale from the clip; re-apply facing after.)
            setPlayerFacingLeft(ring == .northwest)
        }

        let progress = inboundProgress(of: orb)
        orb.node.removeAction(forKey: orbFlightActionKey)

        let start = orb.node.position
        let end = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        // Bend away from the ring the player tapped so the return reads as a deflection.
        let bend = size.width * 0.28 * (ring == .northwest ? -1 : ring == .northeast ? 1 : 0.12)
        let control = CGPoint(x: mid.x + bend, y: mid.y)
        let seconds = max(
            orb.travelSeconds * progress / deflectSpeedMultiplier,
            minimumReturnSeconds
        )

        runFlight(
            on: orb.node,
            start: start,
            control: control,
            end: end,
            duration: seconds,
            startScale: orb.node.xScale,
            endScale: 0.45
        ) { [weak self] in
            self?.resolveMonsterHit(at: end)
        }
    }

    /// Mirrors the player on X. Keeps the UIImage→SKTexture V-inversion on Y.
    private func setPlayerFacingLeft(_ faceLeft: Bool) {
        guard let playerNode else { return }
        let magnitude = abs(playerNode.yScale)
        let scale = magnitude > 0 ? magnitude : 1
        playerNode.xScale = faceLeft ? -scale : scale
        playerNode.yScale = playerNode.correctsUIImageVInversion ? -scale : scale
    }

    /// Wrong ring: dash the orb into the player so the miss visibly lands.
    private func playWrongTap() {
        guard let orb = activeOrb, let playerNode else { return }
        SoundEffectsController.shared.playCommon(event: "error")
        orb.node.removeAction(forKey: orbFlightActionKey)

        let start = orb.node.position
        let end = bodyCenter(of: playerNode, height: playerSpriteHeight)
        runFlight(
            on: orb.node,
            start: start,
            control: CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5),
            end: end,
            duration: wrongTapDashSeconds,
            startScale: orb.node.xScale,
            endScale: 1.15
        ) { [weak self] in
            self?.resolvePlayerHit()
        }
    }

    private func resolveMonsterHit(at position: CGPoint) {
        guard !didEnd else { return }
        removeOrbNode()
        playExplosion(at: position)
        flashNode(enemyNode, color: .orange, actionKey: enemyFlashActionKey)

        let events = engine.registerOrbReachedMonster()
        handle(events)
        if !didEnd, engine.outcome == nil {
            scheduleNextOrb()
        }
    }

    private func resolvePlayerHit() {
        guard !didEnd else { return }
        guard let playerNode else { return }
        let position = activeOrb?.node.position
            ?? bodyCenter(of: playerNode, height: playerSpriteHeight)
        removeOrbNode()
        playDamage(at: position)

        let events = engine.registerOrbHitPlayer()
        handle(events)
        if !didEnd, engine.outcome == nil {
            scheduleNextOrb()
        }
    }

    // MARK: - VFX

    private func playDamage(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "damage", from: playerFx)
        flashNode(playerNode, color: .orange, actionKey: playerFlashActionKey)

        let highlight = HighlightConfig.combatImpact
        let referenceHeight = max(orbBaseSize, playerSpriteHeight * 0.3)
        let burst = SparkleEmitterFactory.makeBurstNode(
            config: highlight,
            referenceHeight: referenceHeight
        )
        burst.position = position
        burst.zPosition = Layer.vfx
        addChild(burst)

        let linger = max(highlight.lifetime * 1.6, 0.7)
        burst.run(.sequence([
            .wait(forDuration: linger),
            .removeFromParent(),
        ]))
    }

    private func playExplosion(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "slash_hit", from: playerFx)
        let circle = SKShapeNode(circleOfRadius: 12)
        circle.fillColor = .yellow
        circle.strokeColor = UIColor.orange
        circle.lineWidth = 2
        circle.position = position
        circle.zPosition = Layer.vfx
        addChild(circle)

        let grow = SKAction.scale(to: 3.5, duration: 0.2)
        let fade = SKAction.fadeOut(withDuration: 0.2)
        circle.run(SKAction.group([grow, fade])) {
            circle.removeFromParent()
        }
    }

    // MARK: - End states

    private func finishWin(starsAwarded: Int) {
        guard !didEnd else { return }
        didEnd = true
        GameLogger.mark(.combat, "deflect win (stars: \(starsAwarded))")
        engine.end()
        removeAction(forKey: nextOrbActionKey)
        removeOrbNode()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "win")
        deflectDelegate?.combatDeflectSceneDidWin(starsAwarded: starsAwarded)
    }

    private func finishLose() {
        guard !didEnd else { return }
        didEnd = true
        GameLogger.mark(.combat, "deflect loss")
        engine.end()
        removeAction(forKey: nextOrbActionKey)
        removeOrbNode()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "lose")
        deflectDelegate?.combatDeflectSceneDidLose()
    }

    private func stopCombatLoop() {
        SoundEffectsController.shared.stopLoop(trackID: activeLoopTrackID)
        activeLoopTrackID = nil
        clearCombatMix()
    }

    private func clearCombatMix() {
        SoundEffectsController.shared.setCombatMixActive(false)
        BackgroundMusicController.shared.setCombatMixActive(false)
    }
}
