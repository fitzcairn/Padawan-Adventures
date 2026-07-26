import QuartzCore
import SpriteKit
import UIKit

protocol CombatSceneDelegate: AnyObject {
    func combatSceneDidUpdateStars(_ stars: Int)
    func combatSceneDidUpdateHealth(_ health: Int)
    func combatSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func combatSceneDidWin(starsAwarded: Int)
    func combatSceneDidLose()
}

/// SpriteKit combat arena: player/enemy sprites, curved shots, slash input, VFX.
final class CombatScene: SKScene {
    private struct ShotVisual {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
        let spawnElapsed: Double
        let travelSeconds: Double
        /// Only shots matching the sequence cue can impact the player.
        let canHitPlayer: Bool
        let node: SKNode
    }

    weak var combatDelegate: CombatSceneDelegate?

    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable
    private let slashMaxSeconds: Double
    private let spriteLibrary: SpriteLibrary
    private let letterSpriteSetLibrary: LetterSpriteSetLibrary
    private let combatSprite: SpriteConfig?
    private let enemySprite: (id: String, config: SpriteConfig)?
    private let wallHeight: CGFloat

    private var engine: CombatMinigameEngine
    private var playerNode: AnimatedSpriteNode!
    private var enemyNode: AnimatedSpriteNode!
    private var shotVisuals: [UUID: ShotVisual] = [:]
    private var slashPoints: [CGPoint] = []
    private var slashLine: SKShapeNode?
    private var slashStartedAt: TimeInterval?
    private var isSlashActive = false
    private var didEnd = false
    private var didSetup = false
    private var lastUpdateTime: TimeInterval?

    private let shotBaseSize: CGFloat = 72
    private let playerFlashActionKey = "playerFlash"
    private let playerCombatLibraryID = "player_combat"
    private let playerSwingAnimationName = "swing"

    init(
        size: CGSize,
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable,
        startingHealth: Int,
        letterSoundRepeatSeconds: Double = CombatMinigameEngine.Config.defaultLetterSoundRepeatSeconds,
        slashMaxSeconds: Double = EnemyConfig.fallbackSlashMaxSeconds,
        spriteLibrary: SpriteLibrary,
        letterSpriteSetLibrary: LetterSpriteSetLibrary,
        combatSprite: SpriteConfig?,
        enemySprite: (id: String, config: SpriteConfig)?,
        wallHeight: CGFloat
    ) {
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.slashMaxSeconds = max(slashMaxSeconds, 0.05)
        self.spriteLibrary = spriteLibrary
        self.letterSpriteSetLibrary = letterSpriteSetLibrary
        self.combatSprite = combatSprite
        self.enemySprite = enemySprite
        self.wallHeight = max(wallHeight, 1)
        self.engine = CombatMinigameEngine(
            config: .init(from: enemyType, letterSoundRepeatSeconds: letterSoundRepeatSeconds),
            startingHealth: startingHealth
        )
        super.init(size: size)
        // Aspect-fit avoids distorting paths when the SKView aspect differs from scene size.
        scaleMode = .aspectFit
        backgroundColor = .black
        isUserInteractionEnabled = true
        // Bottom-left origin — more reliable for path motion than a centered anchorPoint.
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard !didSetup else { return }
        didSetup = true
        buildArena()
        engine.begin()
        publishTimer()
        combatDelegate?.combatSceneDidUpdateStars(0)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetup, !didEnd else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard oldSize != size else { return }
        // Keep the fight running; only re-layout sprites. Live shots keep their paths.
        repositionArenaNodes()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !didEnd else { return }

        if isSlashActive, hasSlashTimedOut(at: currentTime) {
            endSlash()
        }

        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime

        let events = engine.tick(dt: dt)
        for event in events {
            handle(event)
        }
        syncShotMotion()
        publishTimer()
        checkImpacts()
    }

    // MARK: - Layout

    /// 40% screen height × 1.2 (20% larger).
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


    /// Body aim point (feet + half height). AnimatedSpriteNode extends upward from feet.
    private func bodyCenter(of node: AnimatedSpriteNode, height: CGFloat) -> CGPoint {
        CGPoint(x: node.position.x, y: node.position.y + height * 0.5)
    }

    private func buildArena() {
        playerNode?.removeFromParent()
        enemyNode?.removeFromParent()

        let player = AnimatedSpriteNode(
            size: CGSize(width: playerSpriteHeight, height: playerSpriteHeight)
        )
        player.fitHeight(playerSpriteHeight)
        player.zPosition = 10
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

        let enemy = AnimatedSpriteNode(
            size: CGSize(width: enemySpriteHeight, height: enemySpriteHeight)
        )
        enemy.zPosition = 10
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
    }

    /// Pins the sprite's top-most middle opaque pixel to the view's top-middle.
    private func placeEnemyAtTopOfView() {
        guard let enemyNode else { return }
        enemyNode.fitHeight(enemySpriteHeight)
        // Measure from a known position, then shift so content top == scene top.
        enemyNode.position = CGPoint(x: size.width * 0.5, y: 0)
        let frame = enemyNode.calculateAccumulatedFrame()
        let topPadding = topOpaqueInsetPoints(for: enemyNode)
        // Quad top → scene top, then nudge up by transparent padding above content.
        let dy = size.height - frame.maxY + topPadding
        enemyNode.position = CGPoint(x: size.width * 0.5, y: dy)
    }

    /// Transparent padding above the opaque content, in scene points.
    private func topOpaqueInsetPoints(for node: AnimatedSpriteNode) -> CGFloat {
        guard let texture = node.texture else { return 0 }
        let image = texture.cgImage()
        let imageHeight = CGFloat(image.height)
        guard imageHeight > 0 else { return 0 }
        guard let bounds = SpriteSheetLoader.opaqueContentBounds(of: image) else { return 0 }
        let visualHeight = node.size.height * abs(node.yScale)
        return CGFloat(bounds.minY) / imageHeight * visualHeight
    }

    private func repositionArenaNodes() {
        guard playerNode != nil, enemyNode != nil else {
            buildArena()
            return
        }
        playerNode.fitHeight(playerSpriteHeight)
        playerNode.position = playerPosition
        placeEnemyAtTopOfView()
    }

    // MARK: - Engine events

    private func handle(_ event: CombatEngineEvent) {
        switch event {
        case let .sequenceCue(requiredLetter):
            playSequenceCue(requiredLetter: requiredLetter)
        case let .spawnShot(id, travelSeconds, visualLetter):
            spawnShot(id: id, travelSeconds: travelSeconds, visualLetter: visualLetter)
        case .timerTick:
            SoundEffectsController.shared.play(event: "timer_tick", from: playerFx)
        case let .healthChanged(health):
            combatDelegate?.combatSceneDidUpdateHealth(health)
        case .won:
            finishWin()
        case .lost:
            finishLose()
        }
    }

    private func playSequenceCue(requiredLetter: String) {
        // Prefer shared letter-name tracks so combat matches wall / other letter games.
        if let shared = LetterSoundCatalog.nameTrackID(for: requiredLetter) {
            SoundEffectsController.shared.play(trackID: shared)
            return
        }
        if let typeFx = enemyType.shotTypes[requiredLetter]?.fx,
           let trackID = typeFx.trackID(for: "shoot") {
            SoundEffectsController.shared.play(trackID: trackID)
        }
    }

    private func spawnShot(id: UUID, travelSeconds: Double, visualLetter: String) {
        let requiredLetter = engine.shots[id]?.requiredLetter ?? visualLetter
        let canHitPlayer = visualLetter == requiredLetter

        let start = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let end = shotEndPoint(canHitPlayer: canHitPlayer)
        // Matching and miss shots fan across most of the screen width.
        let lateralSpread = canHitPlayer ? size.width * 0.42 : size.width * 0.48
        let lateral = CGFloat.random(in: -lateralSpread...lateralSpread)
        let control = CGPoint(
            x: (start.x + end.x) * 0.5 + lateral,
            y: (start.y + end.y) * 0.5
        )

        let shot: SKNode
        if let glyph = LetterSpriteFactory.sprite(
            letter: visualLetter,
            side: shotBaseSize,
            library: letterSpriteSetLibrary
        ) {
            shot = glyph
        } else {
            let shape = SKShapeNode(rectOf: CGSize(width: shotBaseSize, height: shotBaseSize), cornerRadius: 4)
            shape.fillColor = enemyType.fillColor.withAlphaComponent(0.9)
            shape.strokeColor = .white
            shape.lineWidth = 1.5
            let label = SKLabelNode(text: visualLetter)
            label.fontName = AppFont.name
            label.fontSize = shotBaseSize * 0.62
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.fontColor = .white
            label.zPosition = 1
            shape.addChild(label)
            shot = shape
        }
        shot.position = start
        shot.setScale(0.35)
        shot.zPosition = 20
        shot.name = "shot-\(id.uuidString)"
        addChild(shot)

        shotVisuals[id] = ShotVisual(
            start: start,
            control: control,
            end: end,
            spawnElapsed: engine.elapsed,
            travelSeconds: max(travelSeconds, 0.05),
            canHitPlayer: canHitPlayer,
            node: shot
        )
    }

    /// Matching shots aim at the player body; mismatches fly past near a screen edge.
    private func shotEndPoint(canHitPlayer: Bool) -> CGPoint {
        let player = bodyCenter(of: playerNode, height: playerSpriteHeight)
        guard !canHitPlayer else { return player }

        let side: CGFloat = Bool.random() ? -1 : 1
        let missX = min(
            max(player.x + side * size.width * 0.48, size.width * 0.05),
            size.width * 0.95
        )
        let missY = max(playerNode.position.y - size.height * 0.02, size.height * 0.01)
        return CGPoint(x: missX, y: missY)
    }

    private func syncShotMotion() {
        for (id, visual) in shotVisuals {
            let t = CGFloat(
                min(1, max(0, (engine.elapsed - visual.spawnElapsed) / visual.travelSeconds))
            )
            visual.node.position = quadraticBezier(t: t, start: visual.start, control: visual.control, end: visual.end)
            visual.node.setScale(0.35 + 0.80 * t)
            if t >= 1 {
                finishShotPath(shotID: id)
            }
        }
    }

    private func quadraticBezier(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let u = 1 - t
        let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
        let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private func checkImpacts() {
        guard playerNode != nil else { return }
        let aim = bodyCenter(of: playerNode, height: playerSpriteHeight)
        for (id, visual) in shotVisuals where visual.canHitPlayer {
            let hitRadius = max(shotBaseSize * visual.node.xScale * 0.5, 12)
            let dx = visual.node.position.x - aim.x
            let dy = visual.node.position.y - aim.y
            let playerHitRadius = playerSpriteHeight * 0.45
            if sqrt(dx * dx + dy * dy) <= hitRadius + playerHitRadius {
                resolveImpactIfNeeded(shotID: id)
            }
        }
    }

    private func finishShotPath(shotID: UUID) {
        guard let visual = shotVisuals[shotID] else { return }
        if visual.canHitPlayer {
            resolveImpactIfNeeded(shotID: shotID)
        } else {
            // Missed the player — despawn quietly with no damage VFX.
            engine.discardShot(shotID: shotID)
            removeShotNode(id: shotID)
        }
    }

    private func resolveImpactIfNeeded(shotID: UUID) {
        guard let visual = shotVisuals[shotID], visual.canHitPlayer else { return }
        guard engine.registerImpact(shotID: shotID) else {
            removeShotNode(id: shotID)
            return
        }
        let position = visual.node.position
        removeShotNode(id: shotID)
        playDamage(at: position)
        for pending in engine.drainPendingEvents() {
            handle(pending)
        }
    }

    private func removeShotNode(id: UUID) {
        shotVisuals[id]?.node.removeFromParent()
        shotVisuals[id] = nil
    }

    private func playDamage(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "damage", from: playerFx)
        flashPlayer(color: .orange)

        let highlight = HighlightConfig.combatImpact
        let referenceHeight = max(shotBaseSize, playerSpriteHeight * 0.3)
        let burst = SparkleEmitterFactory.makeBurstNode(
            config: highlight,
            referenceHeight: referenceHeight
        )
        burst.position = position
        burst.zPosition = 40
        addChild(burst)

        let linger = max(highlight.lifetime * 1.6, 0.7)
        burst.run(.sequence([
            .wait(forDuration: linger),
            .removeFromParent(),
        ]))
    }

    /// Temporary colorize pulse on the player sprite.
    private func flashPlayer(color: UIColor, hold: TimeInterval = 0.08, gap: TimeInterval = 0.05) {
        guard let playerNode else { return }
        playerNode.removeAction(forKey: playerFlashActionKey)

        let paint = SKAction.run { [weak playerNode] in
            playerNode?.color = color
            playerNode?.colorBlendFactor = 0.7
        }
        let clear = SKAction.run { [weak playerNode] in
            playerNode?.colorBlendFactor = 0
        }
        let pulse = SKAction.sequence([
            paint,
            SKAction.wait(forDuration: hold),
            clear,
            SKAction.wait(forDuration: gap),
        ])
        playerNode.run(SKAction.sequence([pulse, pulse]), withKey: playerFlashActionKey)
    }

    private func playExplosion(at position: CGPoint) {
        let circle = SKShapeNode(circleOfRadius: 12)
        circle.fillColor = .yellow
        circle.strokeColor = UIColor.orange
        circle.lineWidth = 2
        circle.position = position
        circle.zPosition = 40
        addChild(circle)

        let grow = SKAction.scale(to: 3.5, duration: 0.2)
        let fade = SKAction.fadeOut(withDuration: 0.2)
        circle.run(SKAction.group([grow, fade])) {
            circle.removeFromParent()
        }
    }

    private func playIncorrectSlash(at position: CGPoint) {
        playSlashErrorSound()

        let container = SKNode()
        container.position = position
        container.zPosition = 45
        addChild(container)

        let flash = SKShapeNode(circleOfRadius: 22)
        flash.fillColor = UIColor.systemBlue.withAlphaComponent(0.35)
        flash.strokeColor = UIColor.systemBlue
        flash.lineWidth = 2
        container.addChild(flash)

        // Distinct from the yellow correct explode: a blue "X".
        for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
            let bar = SKShapeNode(rectOf: CGSize(width: 44, height: 6), cornerRadius: 2)
            bar.fillColor = .systemBlue
            bar.strokeColor = .white
            bar.lineWidth = 1
            bar.zRotation = angle
            container.addChild(bar)
        }

        let pop = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.35, duration: 0.08),
                SKAction.fadeAlpha(to: 1, duration: 0.05),
            ]),
            SKAction.wait(forDuration: 0.06),
            SKAction.group([
                SKAction.scale(to: 1.7, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.18),
            ]),
            SKAction.removeFromParent(),
        ])
        container.setScale(0.7)
        container.run(pop)
    }

    private func playSlashErrorSound() {
        SoundEffectsController.shared.playCommon(event: "error")
    }

    // MARK: - Slash input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !engine.isFrozen else { return }
        guard let touch = touches.first else { return }
        beginSlash(at: touch.location(in: self), time: CACurrentMediaTime())
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !engine.isFrozen, isSlashActive else { return }
        guard let touch = touches.first else { return }
        if hasSlashTimedOut(at: CACurrentMediaTime()) {
            endSlash()
            return
        }
        let point = touch.location(in: self)
        slashPoints.append(point)
        updateSlashLine()
        resolveSlashHits()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endSlash()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endSlash()
    }

    private func beginSlash(at point: CGPoint, time: TimeInterval) {
        isSlashActive = true
        slashStartedAt = time
        slashPoints = [point]
        updateSlashLine()
        if combatSprite != nil {
            playerNode.playOnce(
                name: playerSwingAnimationName,
                library: spriteLibrary,
                libraryID: playerCombatLibraryID
            )
            // Left half of the screen → mirror horizontally so the padawan faces that way.
            // (`playOnce` resets scale from the clip; re-apply facing after.)
            setPlayerFacingLeft(point.x < size.width * 0.5)
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

    private func endSlash() {
        isSlashActive = false
        slashStartedAt = nil
        clearSlashLine()
        slashPoints = []
    }

    private func hasSlashTimedOut(at time: TimeInterval) -> Bool {
        guard let started = slashStartedAt else { return false }
        return time - started >= slashMaxSeconds
    }

    private func updateSlashLine() {
        slashLine?.removeFromParent()
        guard slashPoints.count >= 2 else { return }
        let path = CGMutablePath()
        path.move(to: slashPoints[0])
        for p in slashPoints.dropFirst() {
            path.addLine(to: p)
        }
        let line = SKShapeNode(path: path)
        line.strokeColor = UIColor.white.withAlphaComponent(0.85)
        line.lineWidth = 4
        line.lineCap = .round
        line.zPosition = 50
        addChild(line)
        slashLine = line
    }

    private func clearSlashLine() {
        slashLine?.removeFromParent()
        slashLine = nil
    }

    private func resolveSlashHits() {
        guard isSlashActive, slashPoints.count >= 2 else { return }

        // Use the full active stroke so enter→exit across the sprite can be detected.
        let stroke = slashPoints

        for (id, visual) in shotVisuals {
            let side = shotSpriteSide(for: visual.node)
            guard CombatSlashGeometry.slashBisectsSquare(
                points: stroke,
                center: visual.node.position,
                side: side
            ) else {
                continue
            }

            let result = engine.registerSlashHit(shotID: id)
            let pos = visual.node.position
            switch result {
            case .ignored:
                continue
            case .correct:
                removeShotNode(id: id)
                playExplosion(at: pos)
                combatDelegate?.combatSceneDidUpdateStars(engine.combatStars)
                for pending in engine.drainPendingEvents() {
                    handle(pending)
                }
                if engine.hasWon || engine.outcome != nil {
                    finishWin()
                    return
                }
            case .wrong:
                removeShotNode(id: id)
                playIncorrectSlash(at: pos)
            }
        }
    }

    private func shotSpriteSide(for node: SKNode) -> CGFloat {
        shotBaseSize * max(abs(node.xScale), abs(node.yScale))
    }

    // MARK: - End states

    private func publishTimer() {
        let seconds = max(0, Int(ceil(engine.remainingTime - 1e-9)))
        combatDelegate?.combatSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func finishWin() {
        guard !didEnd else { return }
        didEnd = true
        engine.end()
        for id in Array(shotVisuals.keys) {
            removeShotNode(id: id)
        }
        clearSlashLine()
        let awarded = engine.config.starsToWin
        combatDelegate?.combatSceneDidWin(starsAwarded: awarded)
    }

    private func finishLose() {
        guard !didEnd else { return }
        didEnd = true
        engine.end()
        clearSlashLine()
        combatDelegate?.combatSceneDidLose()
    }
}
