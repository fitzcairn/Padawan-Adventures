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
        let node: SKShapeNode
    }

    weak var combatDelegate: CombatSceneDelegate?

    private let enemyType: EnemyTypeConfig
    private let enemyFx: SoundEffectTable
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
        self.enemyFx = enemyType.fx
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
        case let .spawnShot(id, travelSeconds):
            spawnShot(id: id, travelSeconds: travelSeconds)
        case .timerTick:
            SoundEffectsController.shared.play(event: "timer_tick", from: playerFx)
        case .won:
            finishWin()
        case .lost:
            finishLose()
        }
    }

    private func spawnShot(id: UUID, travelSeconds: Double) {
        SoundEffectsController.shared.play(event: "shoot", from: enemyFx)

        let start = enemyNode.position
        let end = playerNode.position
        let lateral = CGFloat.random(in: -size.width * 0.22...size.width * 0.22)
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

        shotVisuals[id] = ShotVisual(
            start: start,
            control: control,
            end: end,
            spawnElapsed: engine.elapsed,
            travelSeconds: max(travelSeconds, 0.05),
            node: shot
        )
    }

    private func syncShotMotion() {
        for (id, visual) in shotVisuals {
            let t = CGFloat(
                min(1, max(0, (engine.elapsed - visual.spawnElapsed) / visual.travelSeconds))
            )
            visual.node.position = quadraticBezier(t: t, start: visual.start, control: visual.control, end: visual.end)
            visual.node.setScale(0.35 + 0.80 * t)
            if t >= 1 {
                resolveImpactIfNeeded(shotID: id)
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
        for (id, visual) in shotVisuals {
            let hitRadius = max(shotBaseSize * visual.node.xScale * 0.5, 12)
            let dx = visual.node.position.x - playerNode.position.x
            let dy = visual.node.position.y - playerNode.position.y
            let playerHitRadius = min(size.width, size.height) * 0.12
            if sqrt(dx * dx + dy * dy) <= hitRadius + playerHitRadius {
                resolveImpactIfNeeded(shotID: id)
            }
        }
    }

    private func resolveImpactIfNeeded(shotID: UUID) {
        guard shotVisuals[shotID] != nil else { return }
        guard engine.registerImpact(shotID: shotID) else {
            removeShotNode(id: shotID)
            return
        }
        let position = shotVisuals[shotID]?.node.position ?? playerNode.position
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
                guard engine.registerSlashHit(shotID: id) else { continue }
                let pos = visual.node.position
                removeShotNode(id: id)
                playExplosion(at: pos)
                combatDelegate?.combatSceneDidUpdateStars(engine.combatStars)
                if engine.hasWon || engine.outcome != nil {
                    finishWin()
                    return
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
