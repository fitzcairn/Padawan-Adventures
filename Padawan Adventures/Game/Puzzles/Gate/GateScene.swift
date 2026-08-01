import SpriteKit
import UIKit

protocol GateSceneDelegate: AnyObject {
    func gateSceneDidSelectWord(_ word: String)
    func gateSceneDidUpdateConnectedPrefix(_ prefix: String)
    func gateSceneDidWin(starsAwarded: Int)
}

/// SpriteKit gate puzzle: staging area, draggable letter tokens.
final class GateScene: MinigameScene {
    static let connectedSoundActionKey = "gateConnectedSound"
    static let wrongMoveActionKey = "gateWrongMove"
    static let winSequenceActionKey = "gateWinSequence"
    static let wrongMoveDuration: TimeInterval = 1.0
    /// Brief beat after the final right-end connector appears, before win SFX / overlay.
    static let winConnectorHoldDuration: TimeInterval = 0.45
    /// How often connector bolts re-jag for the electricity flicker.
    static let electricityRefreshInterval: TimeInterval = 0.045

    weak var gateDelegate: GateSceneDelegate?

    let puzzleConfig: GateSpellingConfig

    var engine: GateMinigameEngine
    var stagingNode: SKShapeNode?
    var leftEndpointNode: SKNode?
    var rightEndpointNode: SKNode?
    var letterNodes: [UUID: SKNode] = [:]
    var connectorSegments: [ElectricConnector] = []
    var electricityRefreshAccumulator: TimeInterval = 0
    var electricityRNG = SystemRandomNumberGenerator()
    var draggedNode: SKNode?
    var dragOffset: CGPoint = .zero
    var dragStartPosition: CGPoint = .zero
    var isCompletingWin = false
    var lastUpdateTime: TimeInterval?
    var activeLoopTrackID: String?
    var lastConnectedPrefix = ""
    /// Connected prefix when the current drag began; used to detect non-advancing moves.
    var connectedPrefixAtDragStart: String?
    var placementRNG = SystemRandomNumberGenerator()

    let capacitorWrongFlash = UIColor.systemRed
    /// Bright blue tint for the completed start → letters → stop chain.
    let capacitorSolvedTint = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1)
    let capacitorTintBlend: CGFloat = 0.55
    /// Fallback circle colors when the capacitor texture fails to load.
    let circleFill = UIColor(white: 0.22, alpha: 1)
    let connectorColor = UIColor(red: 0.55, green: 0.82, blue: 1.0, alpha: 1)
    let connectorCoreColor = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)

    init(
        size: CGSize,
        puzzleConfig: GateSpellingConfig
    ) {
        self.puzzleConfig = puzzleConfig
        self.engine = GateMinigameEngine(config: .init(from: puzzleConfig))
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        engine.begin()
        gateDelegate?.gateSceneDidSelectWord(engine.targetWord)
        GameLogger.step(.world, "gate.buildPuzzle") { buildPuzzle() }
        playWordSound()
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.world, "gate.willMove teardown")
        stopGateLoop()
    }

    override func rebuildLayout() {
        rebuildLayoutPreservingLetters()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime

        refreshElectricityConnectors(dt: dt)
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
        let r = letterCapacitorRadius
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

    func endDrag() {
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
    func animateWrongMove(_ node: SKNode, backTo origin: CGPoint) {
        node.removeAction(forKey: Self.wrongMoveActionKey)
        node.zPosition = 50

        applyCapacitorTint(to: node, color: capacitorWrongFlash, blend: capacitorTintBlend)

        let move = SKAction.move(to: origin, duration: Self.wrongMoveDuration)
        move.timingMode = .easeInEaseOut

        let refreshConnectors = SKAction.customAction(withDuration: Self.wrongMoveDuration) {
            [weak self] _, _ in
            self?.updateCorrectOrderConnectors()
        }

        let finish = SKAction.run { [weak self, weak node] in
            guard let self, let node else { return }
            self.clearCapacitorTint(on: node)
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
    func letterNode(at point: CGPoint) -> SKNode? {
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

    func stagedLettersLeftToRight() -> [(node: SKNode, letter: String)] {
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
    func updateCorrectOrderConnectors() {
        clearConnectorSegments()
        defer { syncArcLoopWithConnectors() }

        guard !didEnd else { return }
        guard let leftEndpointNode, let rightEndpointNode else { return }
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

        applyConnectedCapacitorColors(
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

    /// When the full word chain is complete, tint every linked capacitor bright blue.
    func applyConnectedCapacitorColors(
        staged: [(node: SKNode, letter: String)],
        connectedCount: Int,
        isFullyConnected: Bool
    ) {
        guard let leftEndpointNode, let rightEndpointNode else { return }
        if isFullyConnected {
            applyCapacitorTint(to: leftEndpointNode, color: capacitorSolvedTint, blend: capacitorTintBlend)
            applyCapacitorTint(to: rightEndpointNode, color: capacitorSolvedTint, blend: capacitorTintBlend)
            var solvedNodes = Set<ObjectIdentifier>()
            for index in 0..<connectedCount {
                let node = staged[index].node
                applyCapacitorTint(to: node, color: capacitorSolvedTint, blend: capacitorTintBlend)
                solvedNodes.insert(ObjectIdentifier(node))
            }
            for (_, node) in letterNodes where !solvedNodes.contains(ObjectIdentifier(node)) {
                guard node.action(forKey: Self.wrongMoveActionKey) == nil else { continue }
                clearCapacitorTint(on: node)
            }
            return
        }

        clearCapacitorTint(on: leftEndpointNode)
        clearCapacitorTint(on: rightEndpointNode)
        for (_, node) in letterNodes {
            guard node.action(forKey: Self.wrongMoveActionKey) == nil else { continue }
            clearCapacitorTint(on: node)
        }
    }

    func evaluateWinCondition() {
        guard !didEnd, !isCompletingWin else { return }
        let ordered = stagedLettersLeftToRight().map(\.letter)
        if engine.evaluateStaging(orderedLetters: ordered) {
            beginWinSequence()
        }
    }
}
