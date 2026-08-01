import SpriteKit
import UIKit

protocol GateWordPlugSceneDelegate: AnyObject {
    func gateWordPlugSceneDidWin(starsAwarded: Int)
}

/// SpriteKit gate word-plug puzzle: drag first-letter parts onto word sockets.
final class GateWordPlugScene: SKScene {
    weak var wordPlugDelegate: GateWordPlugSceneDelegate?

    private let puzzleConfig: GateWordPlugConfig
    private let playerFx: SoundEffectTable

    private var engine: GateWordPlugMinigameEngine
    private var plateNodes: [UUID: SKShapeNode] = [:]
    private var socketNodes: [UUID: SKShapeNode] = [:]
    private var tokenNodes: [UUID: SKNode] = [:]
    private var tokenCircles: [UUID: SKShapeNode] = [:]
    private var tokenHome: [UUID: CGPoint] = [:]
    private var laidOutDiameter: CGFloat = 0
    private var laidOutRectSize: CGSize = .zero

    private var didEnd = false
    private var didSetup = false
    private var inputLocked = false

    private var dragTokenID: UUID?
    private var dragStart: CGPoint = .zero
    private var dragOffset: CGPoint = .zero
    private var dragMoved = false

    private let trayHeightRatio: CGFloat = 0.30
    private let columnCount = 2
    private let gridInsetXRatio: CGFloat = 0.04
    private let gridInsetYRatio: CGFloat = 0.06
    private let columnGapRatio: CGFloat = 0.06
    private let rowGapRatio: CGFloat = 0.18
    private let socketWidthShareMax: CGFloat = 0.45
    private let tapMoveThreshold: CGFloat = 10

    private let rectFill = UIColor(red: 0.06, green: 0.14, blue: 0.36, alpha: 1)
    private let rectStroke = UIColor(white: 0.28, alpha: 1)
    private let socketFill = UIColor(white: 0.55, alpha: 1)
    private let socketStroke = UIColor.white
    private let tokenFill = UIColor(white: 0.28, alpha: 1)
    private let tokenStroke = UIColor(white: 0.80, alpha: 1)
    private let solvedFill = UIColor(red: 0.20, green: 0.72, blue: 0.30, alpha: 1)
    private let wrongFill = UIColor.systemRed

    init(
        size: CGSize,
        puzzleConfig: GateWordPlugConfig,
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.engine = GateWordPlugMinigameEngine(config: .init(from: puzzleConfig))
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
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetup, !didEnd else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard oldSize != size else { return }
        rebuildLayout()
    }

    // MARK: - Layout

    private func buildPuzzle() {
        removeAllChildren()
        plateNodes = [:]
        socketNodes = [:]
        tokenNodes = [:]
        tokenCircles = [:]
        tokenHome = [:]

        let slots = engine.slots
        guard !slots.isEmpty else { return }

        let rows = max(1, Int((Double(slots.count) / 2.0).rounded(.up)))
        let playArea = CGRect(
            x: 0,
            y: size.height * trayHeightRatio,
            width: size.width,
            height: size.height * (1 - trayHeightRatio)
        )
        let gridArea = playArea.insetBy(
            dx: size.width * gridInsetXRatio,
            dy: playArea.height * gridInsetYRatio
        )
        let rowSlotHeight = gridArea.height / CGFloat(rows)
        let columnGap = size.width * columnGapRatio
        let cellWidth = (gridArea.width - columnGap) / CGFloat(columnCount)
        let rectHeight = min(rowSlotHeight * (1 - rowGapRatio), cellWidth * socketWidthShareMax)
        let diameter = rectHeight
        let rectWidth = max(1, cellWidth - diameter)
        laidOutDiameter = diameter
        laidOutRectSize = CGSize(width: rectWidth, height: rectHeight)

        for (index, slot) in slots.enumerated() {
            let row = index / columnCount
            let column = index % columnCount
            let rowCenterY = gridArea.maxY - rowSlotHeight * (CGFloat(row) + 0.5)
            let cellMinX = gridArea.minX + CGFloat(column) * (cellWidth + columnGap)

            let socketCenter: CGPoint
            let rectCenter: CGPoint
            if column == 0 {
                socketCenter = CGPoint(x: cellMinX + diameter * 0.5, y: rowCenterY)
                rectCenter = CGPoint(x: cellMinX + diameter + rectWidth * 0.5, y: rowCenterY)
            } else {
                socketCenter = CGPoint(x: cellMinX + rectWidth + diameter * 0.5, y: rowCenterY)
                rectCenter = CGPoint(x: cellMinX + rectWidth * 0.5, y: rowCenterY)
            }

            let plate = SKShapeNode(
                rectOf: CGSize(width: rectWidth, height: rectHeight),
                cornerRadius: rectHeight * 0.12
            )
            plate.fillColor = rectFill
            plate.strokeColor = rectStroke
            plate.lineWidth = max(2, rectHeight * 0.06)
            plate.position = rectCenter
            plate.name = "rect:\(slot.id.uuidString)"
            plate.zPosition = 10
            addChild(plate)
            plateNodes[slot.id] = plate

            let wordLabel = makeFittingWordLabel(
                text: slot.maskedText,
                maxWidth: rectWidth * 0.86,
                preferredFontSize: rectHeight * 0.42
            )
            wordLabel.zPosition = 1
            wordLabel.isUserInteractionEnabled = false
            plate.addChild(wordLabel)

            let socket = SKShapeNode(circleOfRadius: diameter * 0.5)
            socket.fillColor = socketFill
            socket.strokeColor = socketStroke
            socket.lineWidth = max(2, diameter * 0.05)
            socket.position = socketCenter
            socket.name = "socket:\(slot.id.uuidString)"
            socket.zPosition = 10
            addChild(socket)
            socketNodes[slot.id] = socket
        }

        layoutTrayTokens(diameter: diameter)
    }

    private func layoutTrayTokens(diameter: CGFloat) {
        let trayArea = CGRect(
            x: 0,
            y: 0,
            width: size.width,
            height: size.height * trayHeightRatio
        ).insetBy(dx: diameter * 0.6, dy: diameter * 0.6)

        let tokens = engine.tray
        var positions: [CGPoint] = []
        var rng = SystemRandomNumberGenerator()
        let minDistance = diameter * 1.08

        for _ in tokens {
            var placed: CGPoint?
            for _ in 0..<200 {
                let candidate = CGPoint(
                    x: CGFloat.random(in: trayArea.minX...trayArea.maxX, using: &rng),
                    y: CGFloat.random(in: trayArea.minY...trayArea.maxY, using: &rng)
                )
                let overlaps = positions.contains { existing in
                    hypot(existing.x - candidate.x, existing.y - candidate.y) < minDistance
                }
                if !overlaps {
                    placed = candidate
                    break
                }
            }
            if let placed {
                positions.append(placed)
            } else {
                positions = []
                let n = max(tokens.count, 1)
                for i in 0..<tokens.count {
                    positions.append(
                        CGPoint(
                            x: trayArea.minX + trayArea.width * (CGFloat(i) + 0.5) / CGFloat(n),
                            y: trayArea.midY
                        )
                    )
                }
                break
            }
        }

        for (index, token) in tokens.enumerated() {
            let position = index < positions.count
                ? positions[index]
                : CGPoint(x: trayArea.midX, y: trayArea.midY)
            let node = makeTokenNode(token: token, diameter: diameter)
            node.position = position
            addChild(node)
            tokenNodes[token.id] = node
            tokenHome[token.id] = position
        }
    }

    private func makeTokenNode(token: GateWordPlugMinigameEngine.LetterToken, diameter: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "token:\(token.id.uuidString)"
        root.zPosition = 20

        let circle = SKShapeNode(circleOfRadius: diameter * 0.5)
        circle.fillColor = tokenFill
        circle.strokeColor = tokenStroke
        circle.lineWidth = max(2, diameter * 0.05)
        circle.name = "tokenCircle"
        root.addChild(circle)
        tokenCircles[token.id] = circle

        let letter = makeOutlinedLetter(text: token.letter, fontSize: diameter * 0.42)
        letter.zPosition = 1
        letter.isUserInteractionEnabled = false
        root.addChild(letter)

        return root
    }

    private func rebuildLayout() {
        let plugged = engine.plugged
        buildPuzzle()
        for (slotID, letterID) in plugged {
            applySolvedAppearance(slotID: slotID)
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
                token.zPosition = 20
            }
        }
    }

    private func makeFittingWordLabel(text: String, maxWidth: CGFloat, preferredFontSize: CGFloat) -> SKNode {
        var fontSize = preferredFontSize
        var label = makeOutlinedLetter(text: text, fontSize: fontSize)
        while label.calculateAccumulatedFrame().width > maxWidth, fontSize > 8 {
            fontSize *= 0.9
            label = makeOutlinedLetter(text: text, fontSize: fontSize)
        }
        return label
    }

    /// White letter with black outline and a thin inner shadow for readability.
    private func makeOutlinedLetter(text: String, fontSize: CGFloat) -> SKNode {
        let root = SKNode()
        let outlineOffset = max(1.0, fontSize * 0.06)
        let shadowOffset = max(0.75, fontSize * 0.035)

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
                root.addChild(outline)
            }
        }

        let innerShadow = SKLabelNode(text: text)
        innerShadow.fontName = AppFont.name
        innerShadow.fontSize = fontSize
        innerShadow.fontColor = UIColor.black.withAlphaComponent(0.45)
        innerShadow.verticalAlignmentMode = .center
        innerShadow.horizontalAlignmentMode = .center
        innerShadow.position = CGPoint(x: -shadowOffset, y: shadowOffset)
        innerShadow.zPosition = 1
        root.addChild(innerShadow)

        let label = SKLabelNode(text: text)
        label.fontName = AppFont.name
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 2
        root.addChild(label)

        return root
    }

    // MARK: - Hit testing

    private func draggableToken(at point: CGPoint) -> UUID? {
        let radius = laidOutDiameter * 0.5
        guard radius > 0 else { return nil }
        for (id, node) in tokenNodes {
            guard !engine.isTokenPlugged(id) else { continue }
            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            if hypot(dx, dy) <= radius {
                return id
            }
        }
        return nil
    }

    private func plateSlot(at point: CGPoint) -> UUID? {
        let halfW = laidOutRectSize.width * 0.5
        let halfH = laidOutRectSize.height * 0.5
        guard halfW > 0, halfH > 0 else { return nil }
        for (id, node) in plateNodes {
            let bounds = CGRect(
                x: node.position.x - halfW,
                y: node.position.y - halfH,
                width: laidOutRectSize.width,
                height: laidOutRectSize.height
            )
            if bounds.contains(point) {
                return id
            }
        }
        return nil
    }

    private func emptySocket(containing point: CGPoint) -> UUID? {
        let hitRadius = laidOutDiameter * 0.75
        guard hitRadius > 0 else { return nil }
        for (id, node) in socketNodes {
            guard !engine.isSlotFilled(id) else { continue }
            let dx = node.position.x - point.x
            let dy = node.position.y - point.y
            if hypot(dx, dy) <= hitRadius {
                return id
            }
        }
        return nil
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !inputLocked, let touch = touches.first else { return }
        let p = touch.location(in: self)
        if let id = draggableToken(at: p), let node = tokenNodes[id] {
            dragTokenID = id
            dragStart = p
            dragMoved = false
            dragOffset = CGPoint(x: node.position.x - p.x, y: node.position.y - p.y)
            node.zPosition = 100
            return
        }
        if let slotID = plateSlot(at: p) {
            handle(engine.tapWord(slotID: slotID))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !inputLocked, let dragTokenID, let touch = touches.first,
              let node = tokenNodes[dragTokenID] else { return }
        let p = touch.location(in: self)
        if hypot(p.x - dragStart.x, p.y - dragStart.y) > tapMoveThreshold {
            dragMoved = true
        }
        node.position = CGPoint(x: p.x + dragOffset.x, y: p.y + dragOffset.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let id = dragTokenID else { return }
        animateTokenHome(id: id)
        tokenNodes[id]?.zPosition = 20
        dragTokenID = nil
        dragMoved = false
    }

    private func endDrag() {
        guard let id = dragTokenID, let node = tokenNodes[id] else { return }
        defer {
            dragTokenID = nil
            dragMoved = false
            node.zPosition = 20
        }

        if let slotID = emptySocket(containing: node.position) {
            let events = engine.plug(letterID: id, intoSlotID: slotID)
            guard !events.isEmpty else {
                animateTokenHome(id: id)
                return
            }
            handlePlugEvents(events, letterID: id, slotID: slotID)
            return
        }

        if !dragMoved {
            handle(engine.tapLetter(id: id))
        }
        animateTokenHome(id: id)
    }

    // MARK: - Events / feedback

    private func handle(_ events: [GateWordPlugEngineEvent]) {
        guard !events.isEmpty else { return }

        if events.contains(where: {
            if case .playLetterName = $0 { return true }
            return false
        }) {
            runLetterTapFeedback(events)
            return
        }

        if case let .playWordSound(trackID) = events.first {
            inputLocked = true
            var steps: [SKAction] = []
            appendTrackSteps(to: &steps, trackID: trackID)
            steps.append(SKAction.run { [weak self] in self?.inputLocked = false })
            run(SKAction.sequence(steps))
            return
        }

        for event in events {
            handleSingle(event)
        }
    }

    private func handleSingle(_ event: GateWordPlugEngineEvent) {
        switch event {
        case let .playWordSound(trackID):
            SoundEffectsController.shared.play(trackID: trackID)
        case let .playLetterName(trackID), let .playLetterSound(trackID):
            SoundEffectsController.shared.play(trackID: trackID)
        case .playCorrect:
            playCorrectSound()
        case let .speakPhrase(text):
            SpokenPhrasePlayer.shared.speak(text)
        case let .correctPlug(slotID, letterID):
            applySolvedAppearance(slotID: slotID)
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
            }
        case let .incorrectPlug(letterID):
            animateTokenHome(id: letterID)
        case .won:
            finishWon()
        }
    }

    private func runLetterTapFeedback(_ events: [GateWordPlugEngineEvent]) {
        inputLocked = true
        var steps: [SKAction] = []
        for event in events {
            switch event {
            case let .playLetterName(trackID), let .playLetterSound(trackID):
                appendTrackSteps(to: &steps, trackID: trackID)
            default:
                break
            }
        }
        steps.append(SKAction.run { [weak self] in self?.inputLocked = false })
        run(SKAction.sequence(steps))
    }

    private func handlePlugEvents(
        _ events: [GateWordPlugEngineEvent],
        letterID: UUID,
        slotID: UUID
    ) {
        let isCorrect = events.contains {
            if case .correctPlug = $0 { return true }
            return false
        }
        let didWin = events.contains(.won)
        let phrase = events.compactMap { event -> String? in
            if case let .speakPhrase(text) = event { return text }
            return nil
        }.first

        inputLocked = true

        if isCorrect {
            if let socket = socketNodes[slotID], let token = tokenNodes[letterID] {
                token.position = socket.position
            }
            let flash = SKAction.doubleFlash(
                period: 0.18,
                count: 2,
                apply: { [weak self] in
                    self?.plateNodes[slotID]?.fillColor = self?.solvedFill ?? .green
                    self?.socketNodes[slotID]?.fillColor = self?.solvedFill ?? .green
                },
                clear: { [weak self] in
                    self?.plateNodes[slotID]?.fillColor = self?.rectFill ?? .blue
                    self?.socketNodes[slotID]?.fillColor = self?.socketFill ?? .gray
                }
            )
            let feedbackDuration = SoundEffectsController.shared.cueDuration(of: correctSoundTrackID)
            var audioSteps: [SKAction] = [
                SKAction.run { [weak self] in self?.playCorrectSound() },
                SKAction.wait(forDuration: feedbackDuration),
            ]
            if let phrase {
                audioSteps.append(SKAction.run { [weak self] in
                    self?.speak(phrase) {
                        guard let self else { return }
                        self.applySolvedAppearance(slotID: slotID)
                        if didWin {
                            self.finishWon()
                        } else {
                            self.inputLocked = false
                        }
                    }
                })
            } else {
                audioSteps.append(SKAction.run { [weak self] in
                    guard let self else { return }
                    self.applySolvedAppearance(slotID: slotID)
                    if didWin {
                        self.finishWon()
                    } else {
                        self.inputLocked = false
                    }
                })
            }
            run(SKAction.group([
                flash,
                SKAction.sequence(audioSteps),
            ]))
            return
        }

        let flash = SKAction.doubleFlash(
            period: 0.12,
            count: 2,
            apply: { [weak self] in
                self?.tokenCircles[letterID]?.fillColor = self?.wrongFill ?? .red
            },
            clear: { [weak self] in
                self?.tokenCircles[letterID]?.fillColor = self?.tokenFill ?? .darkGray
            }
        )
        let feedbackDuration = SoundEffectsController.shared.cueDuration(of: errorSoundTrackID)
        run(SKAction.sequence([
            SKAction.group([
                flash,
                SKAction.sequence([
                    SKAction.run { [weak self] in self?.playErrorSound() },
                    SKAction.wait(forDuration: feedbackDuration),
                ]),
            ]),
            SKAction.run { [weak self] in
                self?.animateTokenHome(id: letterID)
                self?.inputLocked = false
            },
        ]))
    }

    private func applySolvedAppearance(slotID: UUID) {
        plateNodes[slotID]?.fillColor = solvedFill
        socketNodes[slotID]?.fillColor = solvedFill
    }

    private func animateTokenHome(id: UUID) {
        guard let node = tokenNodes[id], let home = tokenHome[id] else { return }
        node.run(SKAction.move(to: home, duration: 0.15).withTimingMode(.easeOut))
    }

    private var correctSoundTrackID: String? {
        SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx).trackID(for: "correct")
    }

    private var errorSoundTrackID: String? {
        SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx).trackID(for: "error")
    }

    private func playCorrectSound() {
        SoundEffectsController.shared.play(
            event: "correct",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
    }

    private func playErrorSound() {
        SoundEffectsController.shared.play(
            event: "error",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
    }

    private func appendTrackSteps(to steps: inout [SKAction], trackID: String?) {
        guard let trackID, !trackID.isEmpty else { return }
        let duration = SoundEffectsController.shared.cueDuration(of: trackID)
        steps.append(SKAction.run {
            SoundEffectsController.shared.play(trackID: trackID)
        })
        steps.append(SKAction.wait(forDuration: duration))
    }

    private func speak(_ text: String, then next: @escaping () -> Void) {
        var resumed = false
        let resume = {
            if !resumed {
                resumed = true
                next()
            }
        }
        SpokenPhrasePlayer.shared.speak(text) { resume() }
        run(.sequence([.wait(forDuration: 6), .run { resume() }]))
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.playCommon(event: "win")
        if case let .won(stars) = engine.outcome {
            wordPlugDelegate?.gateWordPlugSceneDidWin(starsAwarded: stars)
        } else {
            wordPlugDelegate?.gateWordPlugSceneDidWin(starsAwarded: engine.slots.count)
        }
    }
}

private extension SKAction {
    func withTimingMode(_ mode: SKActionTimingMode) -> SKAction {
        timingMode = mode
        return self
    }
}
