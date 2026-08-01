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
    private struct ShotVisual {
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

    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable
    private let slashMaxSeconds: Double
    private let slashMaxScreenWidthFraction: Double
    private let spriteLibrary: SpriteLibrary
    private let letterSpriteSetLibrary: LetterSpriteSetLibrary
    private let combatSprite: SpriteConfig?
    private let enemySprite: (id: String, config: SpriteConfig)?
    private let wallHeight: CGFloat

    private var engine: CombatMinigameEngine
    private var playerNode: AnimatedSpriteNode?
    private var enemyNode: AnimatedSpriteNode?
    private var shotVisuals: [UUID: ShotVisual] = [:]
    private var slashPoints: [CGPoint] = []
    private var slashPathLength: CGFloat = 0
    private var slashLine: SKNode?
    private var slashStrokes: [SKShapeNode] = []
    /// Test seam: how many times the slash container has been built, to prove it is
    /// reused across a drag rather than rebuilt per touch event.
    private(set) var slashContainerBuildCount = 0
    private var slashStartedAt: TimeInterval?
    private var isSlashActive = false
    private var lastUpdateTime: TimeInterval?
    private var activeLoopTrackID: String?

    private let shotBaseSize: CGFloat = 103.68
    private let playerFlashActionKey = "playerFlash"
    private let playerCombatLibraryID = "player_combat"
    private let playerSwingAnimationName = "swing"
    private let slashFadeOutSeconds: TimeInterval = 0.28

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

    private func placeEnemyAtTopOfView() {
        guard let enemyNode else { return }
        pinToTopOfView(enemyNode, height: enemySpriteHeight)
    }

    private func repositionArenaNodes() {
        guard let playerNode, let enemyNode else {
            buildArena()
            return
        }
        playerNode.fitHeight(playerSpriteHeight)
        playerNode.position = playerPosition
        pinToTopOfView(enemyNode, height: enemySpriteHeight)
    }

    // MARK: - Engine events

    private func handle(_ event: CombatEngineEvent) {
        switch event {
        case let .sequenceCue(requiredLetter):
            playSequenceCue(requiredLetter: requiredLetter)
            // In-flight letters retarget immediately when the spoken cue changes.
            syncShotAiming()
        case let .spawnShot(id, travelSeconds, visualLetter):
            spawnShot(id: id, travelSeconds: travelSeconds, visualLetter: visualLetter)
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
        // shot_types keys are uppercase catalog ids; cues may be lower / mixed case.
        if let typeFx = enemyType.shotTypes[requiredLetter.uppercased()]?.fx,
           let trackID = typeFx.trackID(for: "shoot") {
            SoundEffectsController.shared.play(trackID: trackID)
        }
    }

    private func spawnShot(id: UUID, travelSeconds: Double, visualLetter: String) {
        guard let enemyNode else { return }
        // Aim from the live cue so a just-changed letter already dodges or homes correctly.
        let canHitPlayer = visualLetter == engine.sequenceRequiredLetter
        let travel = max(travelSeconds, 0.05)
        let start = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let end = shotEndPoint(from: start, canHitPlayer: canHitPlayer)
        let control = shotControlPoint(from: start, to: end, canHitPlayer: canHitPlayer)

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
            pathStart: start,
            pathControl: control,
            pathEnd: end,
            pathSpawnElapsed: engine.elapsed,
            pathTravelSeconds: travel,
            scaleSpawnElapsed: engine.elapsed,
            scaleTravelSeconds: travel,
            canHitPlayer: canHitPlayer,
            visualLetter: visualLetter,
            node: shot
        )
    }

    /// Matching shots aim at the player body; mismatches fly clearly off-screen past them.
    private func shotEndPoint(from start: CGPoint, canHitPlayer: Bool) -> CGPoint {
        guard let playerNode else { return start }
        let player = bodyCenter(of: playerNode, height: playerSpriteHeight)
        guard !canHitPlayer else { return player }

        // Pick the side already away from the player so the dodge never crosses them.
        let side: CGFloat = start.x >= player.x ? 1 : -1
        let missX = side < 0 ? -size.width * 0.08 : size.width * 1.08
        let missY = max(player.y - size.height * 0.12, -size.height * 0.05)
        return CGPoint(x: missX, y: missY)
    }

    private func shotControlPoint(from start: CGPoint, to end: CGPoint, canHitPlayer: Bool) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        if canHitPlayer {
            let lateral = CGFloat.random(in: -size.width * 0.42...size.width * 0.42)
            return CGPoint(x: mid.x + lateral, y: mid.y)
        }
        // Strong outward bend so non-targets obviously swerve around the player.
        guard let playerNode else { return mid }
        let player = bodyCenter(of: playerNode, height: playerSpriteHeight)
        let away: CGFloat = start.x >= player.x ? 1 : -1
        let lateral = away * size.width * CGFloat.random(in: 0.40...0.62)
        return CGPoint(x: mid.x + lateral, y: mid.y + size.height * 0.08)
    }

    /// Retarget in-flight letters when they become / stop being the live phonetic cue.
    private func syncShotAiming() {
        let cue = engine.sequenceRequiredLetter
        guard !cue.isEmpty else { return }

        for (id, visual) in shotVisuals {
            let shouldHit = visual.visualLetter == cue
            guard shouldHit != visual.canHitPlayer else { continue }

            let pathT = pathProgress(for: visual)
            let remaining = max(visual.pathTravelSeconds * Double(1 - pathT), 0.35)
            let current = quadraticBezier(
                t: pathT,
                start: visual.pathStart,
                control: visual.pathControl,
                end: visual.pathEnd
            )
            let end = shotEndPoint(from: current, canHitPlayer: shouldHit)
            let control = shotControlPoint(from: current, to: end, canHitPlayer: shouldHit)

            var updated = visual
            updated.pathStart = current
            updated.pathControl = control
            updated.pathEnd = end
            updated.pathSpawnElapsed = engine.elapsed
            updated.pathTravelSeconds = remaining
            updated.canHitPlayer = shouldHit
            updated.node.position = current
            shotVisuals[id] = updated
        }
    }

    private func pathProgress(for visual: ShotVisual) -> CGFloat {
        CGFloat(
            min(1, max(0, (engine.elapsed - visual.pathSpawnElapsed) / max(visual.pathTravelSeconds, 0.05)))
        )
    }

    private func syncShotMotion() {
        for (id, visual) in shotVisuals {
            let pathT = pathProgress(for: visual)
            let scaleT = CGFloat(
                min(1, max(0, (engine.elapsed - visual.scaleSpawnElapsed) / max(visual.scaleTravelSeconds, 0.05)))
            )
            visual.node.position = quadraticBezier(
                t: pathT,
                start: visual.pathStart,
                control: visual.pathControl,
                end: visual.pathEnd
            )
            visual.node.setScale(0.35 + 0.80 * scaleT)
            if pathT >= 1 {
                finishShotPath(shotID: id)
            }
        }
    }

    private func checkImpacts() {
        guard let playerNode else { return }
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
        flashNode(
            playerNode,
            color: color,
            hold: hold,
            gap: gap,
            actionKey: playerFlashActionKey
        )
    }

    private func playExplosion(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "slash_hit", from: playerFx)
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
        let now = CACurrentMediaTime()
        let point = touch.location(in: self)
        let reachedLengthCap = appendSlashPoint(point)
        updateSlashLine()
        resolveSlashHits()
        // Cap by path length and/or duration, then fade the saber out.
        if reachedLengthCap || hasSlashTimedOut(at: now) {
            endSlash()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endSlash()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endSlash()
    }

    private func beginSlash(at point: CGPoint, time: TimeInterval) {
        SoundEffectsController.shared.play(event: "slash", from: playerFx)
        isSlashActive = true
        slashStartedAt = time
        slashPoints = [point]
        slashPathLength = 0
        updateSlashLine()
        if combatSprite != nil, let playerNode {
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
        slashPathLength = 0
    }

    private func hasSlashTimedOut(at time: TimeInterval) -> Bool {
        guard let started = slashStartedAt else { return false }
        return time - started >= slashMaxSeconds
    }

    private var maxSlashPathLength: CGFloat {
        max(size.width * slashMaxScreenWidthFraction, 1)
    }

    /// Appends `point`, clamping to `maxSlashPathLength`. Returns true if the length cap was hit.
    @discardableResult
    private func appendSlashPoint(_ point: CGPoint) -> Bool {
        guard let last = slashPoints.last else {
            slashPoints = [point]
            slashPathLength = 0
            return false
        }
        let dx = point.x - last.x
        let dy = point.y - last.y
        let step = hypot(dx, dy)
        guard step > 0.5 else { return false }

        let maxLen = maxSlashPathLength
        let remaining = maxLen - slashPathLength
        if step >= remaining {
            let t = remaining / step
            slashPoints.append(CGPoint(x: last.x + dx * t, y: last.y + dy * t))
            slashPathLength = maxLen
            return true
        }
        slashPoints.append(point)
        slashPathLength += step
        return false
    }

    private func updateSlashLine() {
        guard slashPoints.count >= 2 else { return }
        let path = makeLightsaberSlashPath(from: slashPoints)
        if slashLine != nil, !slashStrokes.isEmpty {
            for stroke in slashStrokes {
                stroke.path = path
            }
            return
        }
        let slash = makeLightsaberSlashNode(path: path)
        slashStrokes = slash.children.compactMap { $0 as? SKShapeNode }
        slashContainerBuildCount += 1
        addChild(slash)
        slashLine = slash
    }

    /// Test seam: drives `updateSlashLine` without synthesising `UITouch` values.
    func updateSlashLineForTesting(points: [CGPoint]) {
        slashPoints = points
        updateSlashLine()
    }

    /// Also used as a test seam after `updateSlashLineForTesting`.
    func clearSlashLine() {
        guard let slash = slashLine else { return }
        slashLine = nil
        slashStrokes = []
        slash.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: slashFadeOutSeconds),
            SKAction.removeFromParent(),
        ]))
    }

    /// Quadratic arc from first→last sample, bulged through the swipe midpoint for a saber slash.
    private func makeLightsaberSlashPath(from points: [CGPoint]) -> CGPath {
        let start = points[0]
        let end = points[points.count - 1]
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)

        let path = CGMutablePath()
        path.move(to: start)
        guard length > 0.5 else {
            path.addLine(to: end)
            return path
        }

        // Prefer the real mid sample so the arc tracks the finger; fall back to a slight bulge.
        // Keep bulge proportional so short (length-capped) slashes don't balloon visually.
        let midSample = points[points.count / 2]
        let chordMid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        let maxBulge = length * 0.35
        let offsetX = midSample.x - chordMid.x
        let offsetY = midSample.y - chordMid.y
        let sampleOffset = hypot(offsetX, offsetY)
        let control: CGPoint
        if sampleOffset > 1 {
            let pull = min(sampleOffset * 2, maxBulge) / sampleOffset
            control = CGPoint(
                x: chordMid.x + offsetX * pull,
                y: chordMid.y + offsetY * pull
            )
        } else {
            let nx = -dy / length
            let ny = dx / length
            let bulge = min(length * 0.18, maxBulge)
            control = CGPoint(x: chordMid.x + nx * bulge, y: chordMid.y + ny * bulge)
        }
        path.addQuadCurve(to: end, control: control)
        return path
    }

    /// Layered blue glow + blade + white core (additive), Star Wars lightsaber style.
    private func makeLightsaberSlashNode(path: CGPath) -> SKNode {
        let container = SKNode()
        container.zPosition = 50
        container.setScale(1)

        // Scale stroke to slash size so short capped trails don't read as full-screen blooms.
        let strokeScale = min(max(maxSlashPathLength / 80, 0.45), 1)

        let glow = makeGlowStroke(
            path: path,
            lineWidth: 14 * strokeScale,
            color: UIColor(red: 0.15, green: 0.45, blue: 1.0, alpha: 0.55),
            glowWidth: 18 * strokeScale
        )
        let blade = makeGlowStroke(
            path: path,
            lineWidth: 6 * strokeScale,
            color: UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 0.95),
            glowWidth: 6 * strokeScale
        )
        let core = makeGlowStroke(
            path: path,
            lineWidth: 2.5 * strokeScale,
            color: UIColor.white.withAlphaComponent(0.95),
            glowWidth: 1 * strokeScale
        )
        glow.blendMode = .add
        blade.blendMode = .add
        core.blendMode = .add

        container.addChild(glow)
        container.addChild(blade)
        container.addChild(core)
        return container
    }

    private func resolveSlashHits() {
        guard isSlashActive, slashPoints.count >= 2 else { return }

        // Any overlap between the stroke and the letter sprite bounds counts as a hit.
        let stroke = slashPoints

        for (id, visual) in shotVisuals {
            let bounds = shotSpriteBounds(for: visual.node)
            guard CombatSlashGeometry.slashIntersectsRect(points: stroke, rect: bounds) else {
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
                combatDelegate?.combatSceneDidUpdateStars(engine.combatStars)
            }
        }
    }

    /// Axis-aligned bounds of the on-screen letter sprite (scaled size, not the base square).
    private func shotSpriteBounds(for node: SKNode) -> CGRect {
        if let sprite = node as? SKSpriteNode {
            let width = sprite.size.width * abs(sprite.xScale)
            let height = sprite.size.height * abs(sprite.yScale)
            return CGRect(
                x: sprite.position.x - width * 0.5,
                y: sprite.position.y - height * 0.5,
                width: width,
                height: height
            )
        }
        let side = shotBaseSize * max(abs(node.xScale), abs(node.yScale))
        return CGRect(
            x: node.position.x - side * 0.5,
            y: node.position.y - side * 0.5,
            width: side,
            height: side
        )
    }

    // MARK: - End states

    private func finishWin() {
        guard !didEnd else { return }
        didEnd = true
        engine.end()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "win")
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
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "lose")
        clearSlashLine()
        combatDelegate?.combatSceneDidLose()
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
