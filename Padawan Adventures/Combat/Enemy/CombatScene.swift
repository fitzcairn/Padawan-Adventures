import SpriteKit
import UIKit

protocol CombatSceneDelegate: AnyObject {
    func combatSceneDidUpdateStars(_ stars: Int)
    func combatSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func combatSceneDidWin(starsAwarded: Int)
    func combatSceneDidLose()
}

/// SpriteKit combat arena: player/enemy placeholders, curved shots, slash input, VFX.
final class CombatScene: SKScene {
    private struct ShotVisual {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
        let spawnElapsed: Double
        let travelSeconds: Double
        /// Only shots matching the sequence cue can impact the player.
        let canHitPlayer: Bool
        let node: SKShapeNode
    }

    weak var combatDelegate: CombatSceneDelegate?

    private let enemyType: EnemyTypeConfig
    private let playerFx: SoundEffectTable

    private var engine: CombatMinigameEngine
    private var playerNode: SKShapeNode!
    private var enemyNode: SKShapeNode!
    private var shotVisuals: [UUID: ShotVisual] = [:]
    private var slashPoints: [CGPoint] = []
    private var slashLine: SKShapeNode?
    private var didEnd = false
    private var didSetup = false
    private var lastUpdateTime: TimeInterval?

    private let shotBaseSize: CGFloat = 36

    init(
        size: CGSize,
        enemyType: EnemyTypeConfig,
        playerFx: SoundEffectTable
    ) {
        self.enemyType = enemyType
        self.playerFx = playerFx
        self.engine = CombatMinigameEngine(config: .init(from: enemyType))
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
        // Keep the fight running; only re-layout placeholders. Live shots keep their paths.
        repositionArenaNodes()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !didEnd else { return }

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

    private var playerPosition: CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.18)
    }

    private var enemyPosition: CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.82)
    }

    private func buildArena() {
        playerNode?.removeFromParent()
        enemyNode?.removeFromParent()

        let w = size.width
        let h = size.height

        let playerSize = CGSize(width: w * 0.50, height: h * 0.25)
        playerNode = SKShapeNode(rectOf: playerSize, cornerRadius: 8)
        playerNode.fillColor = UIColor(white: 0.35, alpha: 1)
        playerNode.strokeColor = .white
        playerNode.lineWidth = 2
        playerNode.position = playerPosition
        playerNode.zPosition = 10
        playerNode.name = "player"
        addChild(playerNode)

        let playerLabel = SKLabelNode(text: "P")
        playerLabel.fontName = "Helvetica-Bold"
        playerLabel.fontSize = min(playerSize.height * 0.45, 64)
        playerLabel.verticalAlignmentMode = .center
        playerLabel.horizontalAlignmentMode = .center
        playerLabel.fontColor = .white
        playerNode.addChild(playerLabel)

        let enemySize = CGSize(width: w * 0.20, height: h * 0.10)
        enemyNode = SKShapeNode(rectOf: enemySize, cornerRadius: 6)
        enemyNode.fillColor = enemyType.fillColor
        enemyNode.strokeColor = .white
        enemyNode.lineWidth = 2
        enemyNode.position = enemyPosition
        enemyNode.zPosition = 10
        enemyNode.name = "enemy"
        addChild(enemyNode)

        let enemyLabel = SKLabelNode(text: String(enemyType.letterCharacter))
        enemyLabel.fontName = "Helvetica-Bold"
        enemyLabel.fontSize = min(enemySize.height * 0.55, 36)
        enemyLabel.verticalAlignmentMode = .center
        enemyLabel.horizontalAlignmentMode = .center
        enemyLabel.fontColor = .white
        enemyNode.addChild(enemyLabel)
    }

    private func repositionArenaNodes() {
        guard playerNode != nil, enemyNode != nil else {
            buildArena()
            return
        }
        playerNode.position = playerPosition
        enemyNode.position = enemyPosition
        // Resize placeholder shapes to the new scene size.
        let playerSize = CGSize(width: size.width * 0.50, height: size.height * 0.25)
        let enemySize = CGSize(width: size.width * 0.20, height: size.height * 0.10)
        playerNode.path = CGPath(
            roundedRect: CGRect(x: -playerSize.width / 2, y: -playerSize.height / 2, width: playerSize.width, height: playerSize.height),
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        enemyNode.path = CGPath(
            roundedRect: CGRect(x: -enemySize.width / 2, y: -enemySize.height / 2, width: enemySize.width, height: enemySize.height),
            cornerWidth: 6,
            cornerHeight: 6,
            transform: nil
        )
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
        case .won:
            finishWin()
        case .lost:
            finishLose()
        }
    }

    private func playSequenceCue(requiredLetter: String) {
        if let typeFx = enemyType.shotTypes[requiredLetter]?.fx,
           typeFx.trackID(for: "shoot") != nil {
            SoundEffectsController.shared.play(event: "shoot", from: typeFx)
        }
    }

    private func spawnShot(id: UUID, travelSeconds: Double, visualLetter: String) {
        let requiredLetter = engine.shots[id]?.requiredLetter ?? visualLetter
        let canHitPlayer = visualLetter == requiredLetter

        let start = enemyNode.position
        let end = shotEndPoint(canHitPlayer: canHitPlayer)
        // Matching shots curve mildly; misses swing wide to clear the player.
        let lateralSpread = canHitPlayer ? size.width * 0.18 : size.width * 0.34
        let lateral = CGFloat.random(in: -lateralSpread...lateralSpread)
        let control = CGPoint(
            x: (start.x + end.x) * 0.5 + lateral,
            y: (start.y + end.y) * 0.5
        )

        let shot = SKShapeNode(rectOf: CGSize(width: shotBaseSize, height: shotBaseSize), cornerRadius: 4)
        shot.fillColor = enemyType.fillColor.withAlphaComponent(0.9)
        shot.strokeColor = .white
        shot.lineWidth = 1.5
        shot.position = start
        shot.setScale(0.35)
        shot.zPosition = 20
        shot.name = "shot-\(id.uuidString)"
        addChild(shot)

        let label = SKLabelNode(text: visualLetter)
        label.fontName = "Helvetica-Bold"
        label.fontSize = shotBaseSize * 0.62
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.fontColor = .white
        label.zPosition = 1
        shot.addChild(label)

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

    /// Matching shots aim at the player; mismatches fly past on a random side.
    private func shotEndPoint(canHitPlayer: Bool) -> CGPoint {
        let player = playerNode.position
        guard !canHitPlayer else { return player }

        let side: CGFloat = Bool.random() ? -1 : 1
        let missX = player.x + side * size.width * 0.42
        let missY = max(player.y - size.height * 0.12, size.height * 0.02)
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
        for (id, visual) in shotVisuals where visual.canHitPlayer {
            let hitRadius = max(shotBaseSize * visual.node.xScale * 0.5, 12)
            let dx = visual.node.position.x - playerNode.position.x
            let dy = visual.node.position.y - playerNode.position.y
            let playerHitRadius = min(size.width, size.height) * 0.12
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
            _ = engine.registerImpact(shotID: shotID)
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
    }

    private func removeShotNode(id: UUID) {
        shotVisuals[id]?.node.removeFromParent()
        shotVisuals[id] = nil
    }

    private func playDamage(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "damage", from: playerFx)

        let square = SKShapeNode(rectOf: CGSize(width: 48, height: 48))
        square.fillColor = .red
        square.strokeColor = .clear
        square.position = position
        square.zPosition = 40
        addChild(square)

        let spin = SKAction.rotate(byAngle: .pi * 4, duration: 0.5)
        let fade = SKAction.fadeOut(withDuration: 0.5)
        square.run(SKAction.group([spin, fade])) {
            square.removeFromParent()
        }
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
        // Prefer player.yaml mapping; fall back so a missing key never silences feedback.
        let trackID = playerFx.trackID(for: "slash_error") ?? "sfx_slash_error"
        SoundEffectsController.shared.play(trackID: trackID)
    }

    // MARK: - Slash input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !engine.isFrozen else { return }
        guard let touch = touches.first else { return }
        slashPoints = [touch.location(in: self)]
        updateSlashLine()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !engine.isFrozen else { return }
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        slashPoints.append(point)
        updateSlashLine()
        resolveSlashHits()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        clearSlashLine()
        slashPoints = []
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        clearSlashLine()
        slashPoints = []
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
        guard slashPoints.count >= 2 else { return }

        let startIndex = max(0, slashPoints.count - 8)
        let recent = Array(slashPoints[startIndex...])

        for (id, visual) in shotVisuals {
            let hitRadius = slashHitRadius(for: visual.node)
            if slashPolylineHitsCircle(points: recent, center: visual.node.position, radius: hitRadius) {
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
    }

    private func slashHitRadius(for node: SKNode) -> CGFloat {
        let scaled = shotBaseSize * max(abs(node.xScale), abs(node.yScale)) * 0.5
        return max(scaled + 28, 40)
    }

    private func slashPolylineHitsCircle(points: [CGPoint], center: CGPoint, radius: CGFloat) -> Bool {
        guard points.count >= 2 else { return false }
        for i in 1..<points.count {
            if distanceFromPointToSegment(center, points[i - 1], points[i]) <= radius {
                return true
            }
        }
        return false
    }

    private func distanceFromPointToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSq = abx * abx + aby * aby
        guard lengthSq > 0.0001 else {
            let dx = point.x - a.x
            let dy = point.y - a.y
            return sqrt(dx * dx + dy * dy)
        }
        let t = max(0, min(1, ((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSq))
        let proj = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
        let dx = point.x - proj.x
        let dy = point.y - proj.y
        return sqrt(dx * dx + dy * dy)
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
