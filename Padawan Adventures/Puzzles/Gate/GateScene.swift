import SpriteKit
import UIKit

protocol GateSceneDelegate: AnyObject {
    func gateSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func gateSceneDidWin(starsAwarded: Int)
    func gateSceneDidLose()
}

/// SpriteKit gate puzzle: staging area, draggable letter tokens, timer-driven engine.
final class GateScene: SKScene {
    weak var gateDelegate: GateSceneDelegate?

    private let puzzleConfig: GatePuzzleConfig
    private let playerFx: SoundEffectTable

    private var engine: GateMinigameEngine
    private var stagingNode: SKShapeNode!
    private var letterNodes: [UUID: SKNode] = [:]
    private var connectorNodes: [SKShapeNode] = []
    private var draggedNode: SKNode?
    private var dragOffset: CGPoint = .zero
    private var didEnd = false
    private var didSetup = false
    private var lastUpdateTime: TimeInterval?
    private var placementRNG = SystemRandomNumberGenerator()

    private let stagingFill = UIColor(white: 0.35, alpha: 1)
    private let circleFill = UIColor(white: 0.22, alpha: 1)
    private let connectorColor = UIColor(red: 0.55, green: 0.82, blue: 1.0, alpha: 1)

    init(
        size: CGSize,
        puzzleConfig: GatePuzzleConfig,
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.engine = GateMinigameEngine(config: .init(from: puzzleConfig))
        super.init(size: size)
        scaleMode = .aspectFit
        backgroundColor = .black
        isUserInteractionEnabled = true
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard !didSetup else { return }
        didSetup = true
        engine.begin()
        buildPuzzle()
        playWordSound()
        publishTimer()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetup, !didEnd else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard oldSize != size else { return }
        rebuildLayoutPreservingLetters()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !didEnd else { return }

        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime

        let events = engine.tick(dt: dt)
        for event in events {
            handle(event)
        }
        publishTimer()
    }

    // MARK: - Layout

    private var stagingRect: CGRect {
        // Aspect 3:1 landscape, ~40% of screen area.
        let area = size.width * size.height * 0.40
        var width = sqrt(area * 3)
        var height = width / 3
        if width > size.width * 0.9 {
            width = size.width * 0.9
            height = width / 3
        }
        if height > size.height * 0.7 {
            height = size.height * 0.7
            width = height * 3
        }
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }

    private var letterRadius: CGFloat {
        min(size.width, size.height) * 0.07
    }

    private func buildPuzzle() {
        removeAllChildren()
        letterNodes = [:]
        connectorNodes = []

        let rect = stagingRect
        stagingNode = SKShapeNode(rectOf: rect.size, cornerRadius: 10)
        stagingNode.fillColor = stagingFill
        stagingNode.strokeColor = UIColor(white: 0.55, alpha: 1)
        stagingNode.lineWidth = 2
        stagingNode.position = CGPoint(x: rect.midX, y: rect.midY)
        stagingNode.zPosition = 1
        stagingNode.name = "staging"
        addChild(stagingNode)

        let radius = letterRadius
        var placedCenters: [CGPoint] = []
        for token in engine.letters {
            let node = makeLetterNode(token: token, radius: radius)
            let position = placeLetter(radius: radius, avoiding: placedCenters)
            node.position = position
            placedCenters.append(position)
            addChild(node)
            letterNodes[token.id] = node
        }
    }

    private func rebuildLayoutPreservingLetters() {
        let previousPositions = letterNodes.mapValues(\.position)
        buildPuzzle()
        let radius = letterRadius
        var placedCenters: [CGPoint] = []
        // Restore prior positions when still valid and non-overlapping; otherwise re-place.
        for (id, node) in letterNodes {
            if let previous = previousPositions[id],
               isValidLetterPosition(previous, radius: radius, avoiding: placedCenters) {
                node.position = previous
                placedCenters.append(previous)
            } else {
                let position = placeLetter(radius: radius, avoiding: placedCenters)
                node.position = position
                placedCenters.append(position)
            }
        }
        updateCorrectOrderConnectors()
    }

    private func makeLetterNode(token: GateMinigameEngine.LetterToken, radius: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = circleFill
        circle.strokeColor = UIColor(white: 0.65, alpha: 1)
        circle.lineWidth = 2
        circle.zPosition = 0
        root.addChild(circle)

        let label = SKLabelNode(text: token.letter)
        label.fontName = "Helvetica-Bold"
        label.fontSize = radius * 1.35
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        // Labels shouldn't steal the parent's hit testing for drag.
        label.isUserInteractionEnabled = false
        root.addChild(label)

        return root
    }

    /// Minimum center-to-center distance so circles do not overlap (includes a small gap).
    private func minCenterDistance(for radius: CGFloat) -> CGFloat {
        radius * 2 + 6
    }

    private func placeLetter(radius: CGFloat, avoiding occupied: [CGPoint]) -> CGPoint {
        let inset = radius + 8
        let bounds = CGRect(
            x: inset,
            y: inset,
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )

        for _ in 0..<120 {
            let point = CGPoint(
                x: CGFloat.random(in: bounds.minX...bounds.maxX, using: &placementRNG),
                y: CGFloat.random(in: bounds.minY...bounds.maxY, using: &placementRNG)
            )
            if isValidLetterPosition(point, radius: radius, avoiding: occupied) {
                return point
            }
        }

        // Deterministic scan if random placement can't find a free slot.
        let step = minCenterDistance(for: radius)
        var y = bounds.maxY
        while y >= bounds.minY {
            var x = bounds.minX
            while x <= bounds.maxX {
                let point = CGPoint(x: x, y: y)
                if isValidLetterPosition(point, radius: radius, avoiding: occupied) {
                    return point
                }
                x += step
            }
            y -= step
        }

        // Last resort: keep searching with a tighter gap so letters still don't stack.
        return densestFallbackPosition(radius: radius, avoiding: occupied, bounds: bounds)
    }

    private func densestFallbackPosition(
        radius: CGFloat,
        avoiding occupied: [CGPoint],
        bounds: CGRect
    ) -> CGPoint {
        let step = max(radius * 1.5, 8)
        var y = bounds.maxY
        while y >= bounds.minY {
            var x = bounds.minX
            while x <= bounds.maxX {
                let point = CGPoint(x: x, y: y)
                if isValidLetterPosition(point, radius: radius, avoiding: occupied, gap: 1) {
                    return point
                }
                x += step
            }
            y -= step
        }
        // Truly full screen: place at the first in-bounds point farthest from others.
        return farthestPoint(in: bounds, from: occupied) ?? CGPoint(x: bounds.midX, y: bounds.maxY)
    }

    private func farthestPoint(in bounds: CGRect, from occupied: [CGPoint]) -> CGPoint? {
        guard !occupied.isEmpty else {
            return CGPoint(x: bounds.minX, y: bounds.maxY)
        }
        var best: CGPoint?
        var bestScore: CGFloat = -1
        let samples = 24
        for iy in 0...samples {
            for ix in 0...samples {
                let point = CGPoint(
                    x: bounds.minX + (bounds.width * CGFloat(ix) / CGFloat(samples)),
                    y: bounds.minY + (bounds.height * CGFloat(iy) / CGFloat(samples))
                )
                guard isOutsideStaging(point, radius: letterRadius) else { continue }
                let score = occupied.map { hypot($0.x - point.x, $0.y - point.y) }.min() ?? 0
                if score > bestScore {
                    bestScore = score
                    best = point
                }
            }
        }
        return best
    }

    private func isOutsideStaging(_ point: CGPoint, radius: CGFloat) -> Bool {
        let letterBounds = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        return !letterBounds.intersects(stagingRect.insetBy(dx: -4, dy: -4))
    }

    private func isValidLetterPosition(
        _ point: CGPoint,
        radius: CGFloat,
        avoiding occupied: [CGPoint],
        gap: CGFloat? = nil
    ) -> Bool {
        guard point.x >= radius,
              point.y >= radius,
              point.x <= size.width - radius,
              point.y <= size.height - radius else {
            return false
        }
        guard isOutsideStaging(point, radius: radius) else { return false }

        let minDistance = gap.map { radius * 2 + $0 } ?? minCenterDistance(for: radius)
        for other in occupied {
            if hypot(other.x - point.x, other.y - point.y) < minDistance {
                return false
            }
        }
        return true
    }

    // MARK: - Events

    private func handle(_ event: GateEngineEvent) {
        switch event {
        case .timerTick:
            SoundEffectsController.shared.play(event: "timer_tick", from: playerFx)
        case .playWordSound:
            playWordSound()
        case .won:
            break
        case .lost:
            finishLost()
        }
    }

    private func playWordSound() {
        let trackID = engine.targetSoundTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
        engine.markWordSoundPlayed()
    }

    private func publishTimer() {
        let seconds = max(0, Int(ceil(engine.remainingTime - 1e-9)))
        gateDelegate?.gateSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        let winTrack = puzzleConfig.winSound
        if !winTrack.isEmpty {
            SoundEffectsController.shared.play(trackID: winTrack)
        }
        if case let .won(stars) = engine.outcome {
            gateDelegate?.gateSceneDidWin(starsAwarded: stars)
        } else {
            gateDelegate?.gateSceneDidWin(starsAwarded: engine.targetWord.count)
        }
    }

    private func finishLost() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        gateDelegate?.gateSceneDidLose()
    }

    // MARK: - Touch / drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let node = letterNode(at: location) else { return }
        draggedNode = node
        dragOffset = CGPoint(x: node.position.x - location.x, y: node.position.y - location.y)
        node.zPosition = 50
        playWordSound()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, let touch = touches.first, let node = draggedNode else { return }
        let location = touch.location(in: self)
        var next = CGPoint(x: location.x + dragOffset.x, y: location.y + dragOffset.y)
        let r = letterRadius
        next.x = min(max(next.x, r), size.width - r)
        next.y = min(max(next.y, r), size.height - r)
        node.position = next
        updateCorrectOrderConnectors()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    private func endDrag() {
        guard let node = draggedNode else { return }
        node.zPosition = 10
        draggedNode = nil
        updateCorrectOrderConnectors()
        evaluateWinCondition()
    }

    private func letterNode(at point: CGPoint) -> SKNode? {
        let hits = nodes(at: point)
        for hit in hits {
            var current: SKNode? = hit
            while let node = current {
                if let name = node.name, name.hasPrefix("letter:") {
                    return node
                }
                current = node.parent
            }
        }
        return nil
    }

    private func stagedLettersLeftToRight() -> [(node: SKNode, letter: String)] {
        let staging = stagingRect
        var staged: [(node: SKNode, letter: String, x: CGFloat)] = []
        for (_, node) in letterNodes {
            guard staging.contains(node.position) else { continue }
            guard let letter = node.userData?["letter"] as? String else { continue }
            staged.append((node, letter.lowercased(), node.position.x))
        }
        staged.sort { $0.x < $1.x }
        return staged.map { ($0.node, $0.letter) }
    }

    /// Light-blue lines between adjacent staging letters that match the target word in order.
    private func updateCorrectOrderConnectors() {
        for line in connectorNodes {
            line.removeFromParent()
        }
        connectorNodes.removeAll(keepingCapacity: true)

        guard !didEnd else { return }
        let target = Array(engine.targetWord.lowercased())
        guard target.count >= 2 else { return }

        let staged = stagedLettersLeftToRight()
        guard staged.count >= 2 else { return }

        let pairCount = min(staged.count - 1, target.count - 1)
        for index in 0..<pairCount {
            let left = staged[index]
            let right = staged[index + 1]
            guard left.letter == String(target[index]),
                  right.letter == String(target[index + 1]) else {
                continue
            }
            let path = CGMutablePath()
            path.move(to: left.node.position)
            path.addLine(to: right.node.position)
            let line = SKShapeNode(path: path)
            line.strokeColor = connectorColor
            line.lineWidth = 6
            line.lineCap = .round
            line.zPosition = 5
            line.name = "connector"
            addChild(line)
            connectorNodes.append(line)
        }
    }

    private func evaluateWinCondition() {
        guard !didEnd else { return }
        let ordered = stagedLettersLeftToRight().map(\.letter)
        if engine.evaluateStaging(orderedLetters: ordered) {
            finishWon()
        }
    }
}
