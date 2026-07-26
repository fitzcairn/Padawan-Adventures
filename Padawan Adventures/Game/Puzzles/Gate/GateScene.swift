import SpriteKit
import UIKit

protocol GateSceneDelegate: AnyObject {
    func gateSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func gateSceneDidSelectWord(_ word: String)
    func gateSceneDidUpdateConnectedPrefix(_ prefix: String)
    func gateSceneDidWin(starsAwarded: Int)
    func gateSceneDidLose()
}

/// SpriteKit gate puzzle: staging area, draggable letter tokens, timer-driven engine.
final class GateScene: SKScene {
    private static let connectedSoundActionKey = "gateConnectedSound"
    private static let wrongMoveActionKey = "gateWrongMove"
    private static let winSequenceActionKey = "gateWinSequence"
    private static let wrongMoveDuration: TimeInterval = 1.0
    /// Brief beat after the final right-end connector appears, before win SFX / overlay.
    private static let winConnectorHoldDuration: TimeInterval = 0.45

    weak var gateDelegate: GateSceneDelegate?

    private let puzzleConfig: GatePuzzleConfig
    private let playerFx: SoundEffectTable

    private var engine: GateMinigameEngine
    private var stagingNode: SKShapeNode!
    private var leftEndpointNode: SKShapeNode!
    private var rightEndpointNode: SKShapeNode!
    private var letterNodes: [UUID: SKNode] = [:]
    private var connectorNodes: [SKShapeNode] = []
    private var draggedNode: SKNode?
    private var dragOffset: CGPoint = .zero
    private var dragStartPosition: CGPoint = .zero
    private var didEnd = false
    private var isCompletingWin = false
    private var didSetup = false
    private var lastUpdateTime: TimeInterval?
    private var lastConnectedPrefix = ""
    /// Connected prefix when the current drag began; used to detect non-advancing moves.
    private var connectedPrefixAtDragStart: String?
    private var placementRNG = SystemRandomNumberGenerator()

    private let stagingFill = UIColor(white: 0.35, alpha: 1)
    private let circleFill = UIColor(white: 0.22, alpha: 1)
    private let circleWrongFlash = UIColor.systemRed
    /// Bright blue fill for the completed start → letters → stop chain.
    private let circleSolvedFill = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1)
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
        gateDelegate?.gateSceneDidSelectWord(engine.targetWord)
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

    /// Top band reserved for the HUD word/timer (shared screen inset + label height).
    /// SpriteKit Y grows upward, so playable content must stay below `size.height - this`.
    private var topHUDReservedHeight: CGFloat {
        let host = view
        let hostSize = host?.bounds.size ?? size
        let safeArea = host?.safeAreaInsets ?? .zero
        let topInset = ScreenLayout.uiInsets(size: hostSize, safeArea: safeArea).top
        // Matches GateHUDView's 44pt bold word, plus a little breathing room under the label.
        let wordBand: CGFloat = 56
        return topInset + wordBand
    }

    /// Highest Y a letter/endpoint center may use without overlapping the HUD word band.
    private func maxPlayableCenterY(for radius: CGFloat) -> CGFloat {
        size.height - topHUDReservedHeight - radius
    }

    /// Midpoint between the left screen edge and the left side of the staging box.
    private var leftEndpointPosition: CGPoint {
        let rect = stagingRect
        let y = min(size.height * 0.5, maxPlayableCenterY(for: letterRadius))
        return CGPoint(x: rect.minX * 0.5, y: y)
    }

    /// Midpoint between the right side of the staging box and the right screen edge.
    private var rightEndpointPosition: CGPoint {
        let rect = stagingRect
        let y = min(size.height * 0.5, maxPlayableCenterY(for: letterRadius))
        return CGPoint(x: (rect.maxX + size.width) * 0.5, y: y)
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
        leftEndpointNode = makeEndpointCircle(radius: radius, name: "endpoint:left")
        leftEndpointNode.position = leftEndpointPosition
        addChild(leftEndpointNode)

        rightEndpointNode = makeEndpointCircle(radius: radius, name: "endpoint:right")
        rightEndpointNode.position = rightEndpointPosition
        addChild(rightEndpointNode)

        var placedCenters: [CGPoint] = [leftEndpointPosition, rightEndpointPosition]
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
        var placedCenters: [CGPoint] = [leftEndpointPosition, rightEndpointPosition]
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

    private func makeEndpointCircle(radius: CGFloat, name: String) -> SKShapeNode {
        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = circleFill
        circle.strokeColor = UIColor(white: 0.65, alpha: 1)
        circle.lineWidth = 2
        circle.zPosition = 8
        circle.name = name
        circle.isUserInteractionEnabled = false
        return circle
    }

    private func addConnectorLine(from start: CGPoint, to end: CGPoint) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let line = SKShapeNode(path: path)
        line.strokeColor = connectorColor
        line.lineWidth = 6
        line.lineCap = .round
        line.zPosition = 5
        line.name = "connector"
        addChild(line)
        connectorNodes.append(line)
    }

    /// Minimum center-to-center distance so circles do not overlap (includes a small gap).
    private func minCenterDistance(for radius: CGFloat) -> CGFloat {
        radius * 2 + 6
    }

    private func placeLetter(radius: CGFloat, avoiding occupied: [CGPoint]) -> CGPoint {
        let inset = radius + 8
        let maxY = maxPlayableCenterY(for: radius)
        let minY = inset
        let bounds = CGRect(
            x: inset,
            y: minY,
            width: max(size.width - inset * 2, 1),
            height: max(maxY - minY, 1)
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
        let maxY = maxPlayableCenterY(for: radius)
        guard point.x >= radius,
              point.y >= radius,
              point.x <= size.width - radius,
              point.y <= maxY else {
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
        case .won:
            break
        case .lost:
            finishLost()
        }
    }

    private func playWordSound() {
        removeAction(forKey: Self.connectedSoundActionKey)
        let trackID = engine.targetSoundTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    /// Progressive cue for a newly lengthened connected prefix (no full-word spelling replay).
    private func playConnectedPrefixSound(_ prefix: String) {
        removeAction(forKey: Self.connectedSoundActionKey)
        guard !prefix.isEmpty,
              let progressiveID = engine.targetEntry.progressiveTrack(forPrefix: prefix),
              !progressiveID.isEmpty else {
            return
        }
        SoundEffectsController.shared.play(trackID: progressiveID)
    }

    private func publishTimer() {
        let seconds = max(0, Int(ceil(engine.remainingTime - 1e-9)))
        gateDelegate?.gateSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func beginWinSequence() {
        guard !didEnd, !isCompletingWin else { return }
        isCompletingWin = true
        isUserInteractionEnabled = false
        draggedNode = nil
        // Draw the final right-end connector before win SFX / overlay.
        updateCorrectOrderConnectors()
        removeAction(forKey: Self.winSequenceActionKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: Self.winConnectorHoldDuration),
                SKAction.run { [weak self] in self?.finishWon() },
            ]),
            withKey: Self.winSequenceActionKey
        )
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.play(
            event: "win",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
        if case let .won(stars) = engine.outcome {
            gateDelegate?.gateSceneDidWin(starsAwarded: stars)
        } else {
            gateDelegate?.gateSceneDidWin(starsAwarded: engine.targetWord.count)
        }
    }

    private func finishLost() {
        guard !didEnd, !isCompletingWin else { return }
        didEnd = true
        isUserInteractionEnabled = false
        removeAction(forKey: Self.winSequenceActionKey)
        gateDelegate?.gateSceneDidLose()
    }

    // MARK: - Touch / drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isCompletingWin, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let node = letterNode(at: location) else { return }
        guard node.action(forKey: Self.wrongMoveActionKey) == nil else { return }
        draggedNode = node
        dragStartPosition = node.position
        dragOffset = CGPoint(x: node.position.x - location.x, y: node.position.y - location.y)
        node.zPosition = 50
        connectedPrefixAtDragStart = lastConnectedPrefix
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isCompletingWin, let touch = touches.first, let node = draggedNode else { return }
        let location = touch.location(in: self)
        var next = CGPoint(x: location.x + dragOffset.x, y: location.y + dragOffset.y)
        let r = letterRadius
        next.x = min(max(next.x, r), size.width - r)
        next.y = min(max(next.y, r), maxPlayableCenterY(for: r))
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
        guard !isCompletingWin, let node = draggedNode else { return }
        draggedNode = nil
        let prefixBeforeMove = connectedPrefixAtDragStart ?? lastConnectedPrefix
        let origin = dragStartPosition
        connectedPrefixAtDragStart = nil
        updateCorrectOrderConnectors()
        // Non-advancing drop: spelling cue + reject animation back to drag start.
        if lastConnectedPrefix.count <= prefixBeforeMove.count {
            playWordSound()
            animateWrongMove(node, backTo: origin)
            return
        }
        node.zPosition = 10
        evaluateWinCondition()
    }

    /// Flash the letter red and ease it back to `origin` over 1s.
    private func animateWrongMove(_ node: SKNode, backTo origin: CGPoint) {
        node.removeAction(forKey: Self.wrongMoveActionKey)
        node.zPosition = 50

        let circle = letterCircle(in: node)
        circle?.fillColor = circleWrongFlash

        let move = SKAction.move(to: origin, duration: Self.wrongMoveDuration)
        move.timingMode = .easeInEaseOut

        let refreshConnectors = SKAction.customAction(withDuration: Self.wrongMoveDuration) {
            [weak self] _, _ in
            self?.updateCorrectOrderConnectors()
        }

        let finish = SKAction.run { [weak self, weak node] in
            guard let self, let node else { return }
            self.letterCircle(in: node)?.fillColor = self.circleFill
            node.zPosition = 10
            self.updateCorrectOrderConnectors()
        }

        node.run(
            SKAction.sequence([
                SKAction.group([move, refreshConnectors]),
                finish,
            ]),
            withKey: Self.wrongMoveActionKey
        )
    }

    private func letterCircle(in root: SKNode) -> SKShapeNode? {
        root.children.compactMap { $0 as? SKShapeNode }.first
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

    /// Light-blue lines for the connected prefix: left end → letters → right end (when complete).
    private func updateCorrectOrderConnectors() {
        for line in connectorNodes {
            line.removeFromParent()
        }
        connectorNodes.removeAll(keepingCapacity: true)

        guard !didEnd else { return }
        let staged = stagedLettersLeftToRight()
        let ordered = staged.map(\.letter)
        let prefix = GateMinigameEngine.connectedPrefix(
            orderedLetters: ordered,
            targetWord: engine.targetWord
        )

        let target = Array(engine.targetWord.lowercased())
        let connectedCount = prefix.count

        // Left endpoint → first correctly placed letter.
        if connectedCount >= 1, let first = staged.first {
            addConnectorLine(from: leftEndpointNode.position, to: first.node.position)
        }

        // Adjacent correct staging letters.
        if connectedCount >= 2 {
            for index in 0..<(connectedCount - 1) {
                let left = staged[index]
                let right = staged[index + 1]
                guard left.letter == String(target[index]),
                      right.letter == String(target[index + 1]) else {
                    continue
                }
                addConnectorLine(from: left.node.position, to: right.node.position)
            }
        }

        // Last correct letter → right endpoint (circuit complete).
        let isFullyConnected = connectedCount == target.count && connectedCount >= 1
        if isFullyConnected {
            let last = staged[connectedCount - 1]
            addConnectorLine(from: last.node.position, to: rightEndpointNode.position)
        }

        applyConnectedCircleColors(
            staged: staged,
            connectedCount: connectedCount,
            isFullyConnected: isFullyConnected
        )

        if prefix != lastConnectedPrefix {
            lastConnectedPrefix = prefix
            gateDelegate?.gateSceneDidUpdateConnectedPrefix(prefix)
            if !prefix.isEmpty {
                playConnectedPrefixSound(prefix)
            }
        }
    }

    /// When the full word chain is complete, paint every linked circle bright blue.
    private func applyConnectedCircleColors(
        staged: [(node: SKNode, letter: String)],
        connectedCount: Int,
        isFullyConnected: Bool
    ) {
        if isFullyConnected {
            leftEndpointNode.fillColor = circleSolvedFill
            rightEndpointNode.fillColor = circleSolvedFill
            var solvedNodes = Set<ObjectIdentifier>()
            for index in 0..<connectedCount {
                let node = staged[index].node
                letterCircle(in: node)?.fillColor = circleSolvedFill
                solvedNodes.insert(ObjectIdentifier(node))
            }
            for (_, node) in letterNodes where !solvedNodes.contains(ObjectIdentifier(node)) {
                guard node.action(forKey: Self.wrongMoveActionKey) == nil else { continue }
                letterCircle(in: node)?.fillColor = circleFill
            }
            return
        }

        leftEndpointNode.fillColor = circleFill
        rightEndpointNode.fillColor = circleFill
        for (_, node) in letterNodes {
            guard node.action(forKey: Self.wrongMoveActionKey) == nil else { continue }
            letterCircle(in: node)?.fillColor = circleFill
        }
    }

    private func evaluateWinCondition() {
        guard !didEnd, !isCompletingWin else { return }
        let ordered = stagedLettersLeftToRight().map(\.letter)
        if engine.evaluateStaging(orderedLetters: ordered) {
            beginWinSequence()
        }
    }
}
