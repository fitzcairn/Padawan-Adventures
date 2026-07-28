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
    /// How often connector bolts re-jag for the electricity flicker.
    private static let electricityRefreshInterval: TimeInterval = 0.045

    weak var gateDelegate: GateSceneDelegate?

    private let puzzleConfig: GateSpellingConfig
    private let playerFx: SoundEffectTable

    private var engine: GateMinigameEngine
    private var stagingNode: SKShapeNode!
    private var leftEndpointNode: SKNode!
    private var rightEndpointNode: SKNode!
    private var letterNodes: [UUID: SKNode] = [:]
    private var connectorSegments: [ElectricConnector] = []
    private var electricityRefreshAccumulator: TimeInterval = 0
    private var electricityRNG = SystemRandomNumberGenerator()
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
    private var capacitorTexture: SKTexture?

    private let capacitorWrongFlash = UIColor.systemRed
    /// Bright blue tint for the completed start → letters → stop chain.
    private let capacitorSolvedTint = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1)
    private let capacitorTintBlend: CGFloat = 0.55
    /// Fallback circle colors when the capacitor texture fails to load.
    private let circleFill = UIColor(white: 0.22, alpha: 1)
    private let connectorColor = UIColor(red: 0.55, green: 0.82, blue: 1.0, alpha: 1)
    private let connectorCoreColor = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)

    /// One light-blue electricity span between two linked capacitors.
    private struct ElectricConnector {
        var start: CGPoint
        var end: CGPoint
        let container: SKNode
        let baseline: SKShapeNode
        let glow: SKShapeNode
        let bolt: SKShapeNode
        let core: SKShapeNode
        let branch: SKShapeNode
    }

    init(
        size: CGSize,
        puzzleConfig: GateSpellingConfig,
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
        let dt = lastUpdateTime.map { min(max(currentTime - $0, 0), 0.05) } ?? (1.0 / 60.0)
        lastUpdateTime = currentTime

        refreshElectricityConnectors(dt: dt)

        guard !didEnd else { return }

        let events = engine.tick(dt: dt)
        for event in events {
            handle(event)
        }
        publishTimer()
    }

    // MARK: - Layout

    private var stagingRect: CGRect {
        // Aspect 3:1 landscape, ~40% of screen area, then shrunk 25%.
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
        width *= 0.75
        height *= 0.75
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }

    /// Base token radius before letter/endpoint size adjustments.
    private var letterRadius: CGFloat {
        min(size.width, size.height) * 0.07
    }

    /// Letter capacitors are 40% larger than the base radius.
    private var letterCapacitorRadius: CGFloat {
        letterRadius * 1.4
    }

    /// Empty side capacitors are 40% smaller than the base radius.
    private var endpointCapacitorRadius: CGFloat {
        letterRadius * 0.6
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
        let y = min(size.height * 0.5, maxPlayableCenterY(for: endpointCapacitorRadius))
        return CGPoint(x: rect.minX * 0.5, y: y)
    }

    /// Midpoint between the right side of the staging box and the right screen edge.
    private var rightEndpointPosition: CGPoint {
        let rect = stagingRect
        let y = min(size.height * 0.5, maxPlayableCenterY(for: endpointCapacitorRadius))
        return CGPoint(x: (rect.maxX + size.width) * 0.5, y: y)
    }

    private func buildPuzzle() {
        removeAllChildren()
        letterNodes = [:]
        connectorSegments = []
        electricityRefreshAccumulator = 0
        if capacitorTexture == nil {
            capacitorTexture = GateSpellingCapacitorSprites.load()
        }

        if let background = GateMinigameBackground.spelling(sceneSize: size) {
            addChild(background)
        }

        let rect = stagingRect
        stagingNode = SKShapeNode(rectOf: rect.size, cornerRadius: 10)
        stagingNode.fillColor = .clear
        stagingNode.strokeColor = .clear
        stagingNode.lineWidth = 0
        stagingNode.position = CGPoint(x: rect.midX, y: rect.midY)
        stagingNode.zPosition = 1
        stagingNode.name = "staging"
        addChild(stagingNode)

        leftEndpointNode = makeEndpointNode(radius: endpointCapacitorRadius, name: "endpoint:left")
        leftEndpointNode.position = leftEndpointPosition
        addChild(leftEndpointNode)

        rightEndpointNode = makeEndpointNode(radius: endpointCapacitorRadius, name: "endpoint:right")
        rightEndpointNode.position = rightEndpointPosition
        addChild(rightEndpointNode)

        let radius = letterCapacitorRadius
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
        let radius = letterCapacitorRadius
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

        var labelOffsetY: CGFloat = 0
        if let texture = capacitorTexture,
           let capacitor = GateSpellingCapacitorSprites.sprite(texture: texture, side: radius * 2) {
            capacitor.zPosition = 0
            root.addChild(capacitor)
            labelOffsetY = GateSpellingCapacitorSprites.letterOffsetY(for: capacitor.size.height)
        } else {
            let circle = SKShapeNode(circleOfRadius: radius)
            circle.fillColor = circleFill
            circle.strokeColor = UIColor(white: 0.65, alpha: 1)
            circle.lineWidth = 2
            circle.zPosition = 0
            circle.name = "capacitorFallback"
            root.addChild(circle)
        }

        let fontSize = radius * 1.35 * 0.85
        let letter = makeOutlinedLetter(text: token.letter, fontSize: fontSize)
        letter.position = CGPoint(x: 0, y: labelOffsetY)
        letter.zPosition = 1
        letter.isUserInteractionEnabled = false
        root.addChild(letter)

        return root
    }

    /// White letter with a black outline for readability on the capacitor face.
    private func makeOutlinedLetter(text: String, fontSize: CGFloat) -> SKNode {
        let root = SKNode()
        let outlineOffset = max(1.0, fontSize * 0.06)

        for dx in -1...1 {
            for dy in -1...1 {
                guard dx != 0 || dy != 0 else { continue }
                let outline = SKLabelNode(text: text)
                outline.fontName = AppFont.name
                outline.fontSize = fontSize
                outline.fontColor = .black
                outline.verticalAlignmentMode = .center
                outline.horizontalAlignmentMode = .center
                outline.position = CGPoint(
                    x: CGFloat(dx) * outlineOffset,
                    y: CGFloat(dy) * outlineOffset
                )
                outline.zPosition = 0
                outline.isUserInteractionEnabled = false
                root.addChild(outline)
            }
        }

        let label = SKLabelNode(text: text)
        label.fontName = AppFont.name
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        label.isUserInteractionEnabled = false
        root.addChild(label)

        return root
    }

    private func makeEndpointNode(radius: CGFloat, name: String) -> SKNode {
        if let texture = capacitorTexture,
           let capacitor = GateSpellingCapacitorSprites.sprite(texture: texture, side: radius * 2) {
            let root = SKNode()
            root.name = name
            root.zPosition = 8
            root.isUserInteractionEnabled = false
            capacitor.zPosition = 0
            root.addChild(capacitor)
            return root
        }

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
        let container = SKNode()
        container.name = "connector"
        container.zPosition = 5

        let baseline = makeConnectorStrokeNode(
            lineWidth: 4,
            color: connectorColor.withAlphaComponent(0.35),
            glowWidth: 0
        )
        let glow = makeConnectorStrokeNode(
            lineWidth: 10,
            color: connectorColor.withAlphaComponent(0.45),
            glowWidth: 6
        )
        let bolt = makeConnectorStrokeNode(
            lineWidth: 4.5,
            color: connectorColor,
            glowWidth: 2
        )
        let core = makeConnectorStrokeNode(
            lineWidth: 1.8,
            color: connectorCoreColor,
            glowWidth: 0
        )
        let branch = makeConnectorStrokeNode(
            lineWidth: 2.2,
            color: connectorColor.withAlphaComponent(0.9),
            glowWidth: 1
        )
        glow.blendMode = .add
        bolt.blendMode = .add
        core.blendMode = .add
        branch.blendMode = .add

        container.addChild(baseline)
        container.addChild(glow)
        container.addChild(bolt)
        container.addChild(core)
        container.addChild(branch)
        addChild(container)

        var connector = ElectricConnector(
            start: start,
            end: end,
            container: container,
            baseline: baseline,
            glow: glow,
            bolt: bolt,
            core: core,
            branch: branch
        )
        applyElectricityPaths(to: &connector)
        connectorSegments.append(connector)
    }

    private func makeConnectorStrokeNode(
        lineWidth: CGFloat,
        color: UIColor,
        glowWidth: CGFloat
    ) -> SKShapeNode {
        let node = SKShapeNode()
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = lineWidth
        node.lineCap = .round
        node.lineJoin = .round
        node.glowWidth = glowWidth
        node.isAntialiased = true
        return node
    }

    private func clearConnectorSegments() {
        for segment in connectorSegments {
            segment.container.removeFromParent()
        }
        connectorSegments.removeAll(keepingCapacity: true)
        electricityRefreshAccumulator = 0
    }

    /// Flicker / re-jag active connectors so the spans read as arcing electricity.
    private func refreshElectricityConnectors(dt: TimeInterval) {
        guard !connectorSegments.isEmpty else { return }
        electricityRefreshAccumulator += dt
        guard electricityRefreshAccumulator >= Self.electricityRefreshInterval else { return }
        electricityRefreshAccumulator = 0
        for index in connectorSegments.indices {
            applyElectricityPaths(to: &connectorSegments[index])
        }
    }

    private func applyElectricityPaths(to connector: inout ElectricConnector) {
        let start = connector.start
        let end = connector.end

        let straight = CGMutablePath()
        straight.move(to: start)
        straight.addLine(to: end)
        connector.baseline.path = straight

        let boltPath = makeElectricityPath(from: start, to: end, using: &electricityRNG)
        connector.glow.path = boltPath
        connector.bolt.path = boltPath
        connector.core.path = boltPath

        // Brightness flicker — keeps the arc feeling alive between re-jags.
        let boltAlpha = CGFloat.random(in: 0.72...1.0, using: &electricityRNG)
        let coreAlpha = CGFloat.random(in: 0.55...1.0, using: &electricityRNG)
        connector.bolt.alpha = boltAlpha
        connector.core.alpha = coreAlpha
        connector.glow.alpha = CGFloat.random(in: 0.35...0.7, using: &electricityRNG)

        // Occasional short side-arc branching off the main span.
        if CGFloat.random(in: 0...1, using: &electricityRNG) < 0.32,
           let branchPath = makeElectricityBranchPath(from: start, to: end, using: &electricityRNG) {
            connector.branch.path = branchPath
            connector.branch.alpha = CGFloat.random(in: 0.35...0.85, using: &electricityRNG)
            connector.branch.isHidden = false
        } else {
            connector.branch.path = nil
            connector.branch.isHidden = true
        }
    }

    /// Jagged polyline along `start`→`end`, with displacement tapered at both endpoints.
    private func makeElectricityPath(
        from start: CGPoint,
        to end: CGPoint,
        using rng: inout some RandomNumberGenerator
    ) -> CGPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let path = CGMutablePath()
        path.move(to: start)
        guard length > 2 else {
            path.addLine(to: end)
            return path
        }

        // Unit perpendicular for lateral bolt displacement.
        let px = -dy / length
        let py = dx / length

        let jagCount = max(Int(length / 16), 3)
        let maxOffset = min(length * 0.14, 14)

        for step in 1..<jagCount {
            let t = CGFloat(step) / CGFloat(jagCount)
            // Soft envelope so the bolt stays anchored at the capacitors.
            let taper = sin(t * .pi)
            let offset = CGFloat.random(in: -maxOffset...maxOffset, using: &rng) * taper
            // Slight uneven progress along the span (not perfectly even segments).
            let alongJitter = CGFloat.random(in: -0.04...0.04, using: &rng) * (1 - abs(t - 0.5) * 2)
            let along = min(max(t + alongJitter, 0.02), 0.98)
            path.addLine(to: CGPoint(
                x: start.x + dx * along + px * offset,
                y: start.y + dy * along + py * offset
            ))
        }
        path.addLine(to: end)
        return path
    }

    /// Short fork that peels off the main span, then dies out — reads as a secondary arc.
    private func makeElectricityBranchPath(
        from start: CGPoint,
        to end: CGPoint,
        using rng: inout some RandomNumberGenerator
    ) -> CGPath? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 28 else { return nil }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        let branchStartT = CGFloat.random(in: 0.25...0.7, using: &rng)
        let origin = CGPoint(
            x: start.x + dx * branchStartT,
            y: start.y + dy * branchStartT
        )
        let branchLength = length * CGFloat.random(in: 0.18...0.38, using: &rng)
        let side: CGFloat = Bool.random(using: &rng) ? 1 : -1
        let tip = CGPoint(
            x: origin.x + ux * branchLength * CGFloat.random(in: 0.35...0.8, using: &rng)
                + px * side * branchLength * CGFloat.random(in: 0.45...0.95, using: &rng),
            y: origin.y + uy * branchLength * CGFloat.random(in: 0.35...0.8, using: &rng)
                + py * side * branchLength * CGFloat.random(in: 0.45...0.95, using: &rng)
        )
        return makeElectricityPath(from: origin, to: tip, using: &rng)
    }

    /// Minimum center-to-center distance so capacitors do not overlap (includes a small gap).
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
                guard isOutsideStaging(point, radius: letterCapacitorRadius) else { continue }
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

    private func capacitorSprite(in root: SKNode) -> SKSpriteNode? {
        root.childNode(withName: "capacitor") as? SKSpriteNode
    }

    private func capacitorFallback(in root: SKNode) -> SKShapeNode? {
        (root.childNode(withName: "capacitorFallback") as? SKShapeNode)
            ?? root.children.compactMap { $0 as? SKShapeNode }.first
            ?? (root as? SKShapeNode)
    }

    private func applyCapacitorTint(to root: SKNode, color: UIColor, blend: CGFloat) {
        if let sprite = capacitorSprite(in: root) {
            sprite.color = color
            sprite.colorBlendFactor = blend
            return
        }
        capacitorFallback(in: root)?.fillColor = color
    }

    private func clearCapacitorTint(on root: SKNode) {
        if let sprite = capacitorSprite(in: root) {
            sprite.colorBlendFactor = 0
            return
        }
        capacitorFallback(in: root)?.fillColor = circleFill
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
        clearConnectorSegments()

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
    private func applyConnectedCapacitorColors(
        staged: [(node: SKNode, letter: String)],
        connectedCount: Int,
        isFullyConnected: Bool
    ) {
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

    private func evaluateWinCondition() {
        guard !didEnd, !isCompletingWin else { return }
        let ordered = stagedLettersLeftToRight().map(\.letter)
        if engine.evaluateStaging(orderedLetters: ordered) {
            beginWinSequence()
        }
    }
}
