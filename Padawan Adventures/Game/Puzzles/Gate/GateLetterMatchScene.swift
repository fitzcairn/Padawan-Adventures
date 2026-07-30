import SpriteKit
import UIKit

protocol GateLetterMatchSceneDelegate: AnyObject {
    func gateLetterMatchSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func gateLetterMatchSceneDidWin(starsAwarded: Int)
    func gateLetterMatchSceneDidLose()
}

/// SpriteKit gate letter-match puzzle: switch letter buttons, timer-driven engine.
final class GateLetterMatchScene: SKScene {
    weak var letterMatchDelegate: GateLetterMatchSceneDelegate?

    private let puzzleConfig: GateLetterMatchConfig
    private let playerFx: SoundEffectTable

    private var engine: GateLetterMatchMinigameEngine
    private var replayBoxNode: SKNode!
    private var letterNodes: [UUID: SKNode] = [:]
    private var switchNodes: [UUID: SKSpriteNode] = [:]
    private var switchTextures: GateLetterMatchSwitchSprites.Textures?
    /// Side length used by the last `layoutLetterRow` (for hit-testing).
    private var laidOutTileSide: CGFloat = 0
    private var didEnd = false
    private var didSetup = false
    private var inputLocked = false
    private var lastUpdateTime: TimeInterval?

    private let replayFill = UIColor(white: 0.28, alpha: 1)
    private let squareFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    private let squareMatchedFill = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    private let squareWrongFill = UIColor.systemRed

    init(
        size: CGSize,
        puzzleConfig: GateLetterMatchConfig,
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.engine = GateLetterMatchMinigameEngine(config: .init(from: puzzleConfig))
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
        playTargetPronunciation()
        publishTimer()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetup, !didEnd else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard oldSize != size else { return }
        rebuildLayout()
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

    /// Fit bounds for the letter row — background image frame when available.
    private var letterRowBounds: CGRect {
        if let bg = GateMinigameBackground.letterMatchFrame(sceneSize: size), bg.width > 1 {
            return bg
        }
        // Aspect 3:1 landscape fallback, ~40% of screen area.
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

    /// Aesthetic target size before fitting into the background width.
    private var preferredTileSize: CGFloat {
        let bounds = letterRowBounds
        let maxByHeight = bounds.height * 0.55
        return min(maxByHeight, min(size.width, size.height) * 0.18) * 1.344
    }

    /// Preferred gap as a fraction of tile side; compress toward `minGapRatio` before shrinking tiles.
    private let preferredGapRatio: CGFloat = 0.18
    private let minGapRatio: CGFloat = 0.04
    /// Horizontal inset inside the background so switches don't kiss the art edges.
    private let backgroundEdgeInsetRatio: CGFloat = 0.05

    private struct LetterRowLayout {
        let side: CGFloat
        let gap: CGFloat
        let firstCenterX: CGFloat
        let centerY: CGFloat
    }

    /// Compresses horizontal padding first; shrinks sprite size only after padding hits the floor.
    private func letterRowLayout(letterCount: Int) -> LetterRowLayout {
        let count = max(letterCount, 1)
        let n = CGFloat(count)
        let bounds = letterRowBounds
        let availableWidth = bounds.width * (1 - 2 * backgroundEdgeInsetRatio)

        var side = preferredTileSize
        var gap = side * preferredGapRatio

        func rowWidth(side: CGFloat, gap: CGFloat) -> CGFloat {
            n * side + max(n - 1, 0) * gap
        }

        if rowWidth(side: side, gap: gap) > availableWidth {
            let minGap = side * minGapRatio
            if count > 1, rowWidth(side: side, gap: minGap) <= availableWidth {
                gap = max(minGap, (availableWidth - n * side) / (n - 1))
            } else {
                // Out of padding room — shrink tiles, keeping min gap ratio.
                let denom = n + max(n - 1, 0) * minGapRatio
                side = max(1, availableWidth / max(denom, 1))
                gap = count > 1 ? side * minGapRatio : 0
            }
        }

        let totalWidth = rowWidth(side: side, gap: gap)
        let firstCenterX = bounds.midX - totalWidth * 0.5 + side * 0.5
        return LetterRowLayout(
            side: side,
            gap: gap,
            firstCenterX: firstCenterX,
            centerY: bounds.midY
        )
    }

    private var replayBoxSize: CGSize {
        let width = min(size.width * 0.28, 160)
        let height = min(size.height * 0.10, 56)
        return CGSize(width: max(width, 96), height: max(height, 44))
    }

    private var replayBoxRect: CGRect {
        let box = replayBoxSize
        // Sit below the timer HUD (upper-trailing) and centered horizontally near the top.
        let topInset = max(size.height * 0.06, 28)
        return CGRect(
            x: (size.width - box.width) * 0.5,
            y: size.height - topInset - box.height,
            width: box.width,
            height: box.height
        )
    }

    private func buildPuzzle() {
        removeAllChildren()
        letterNodes = [:]
        switchNodes = [:]
        switchTextures = GateLetterMatchSwitchSprites.load()

        if let background = GateMinigameBackground.letterMatch(sceneSize: size) {
            background.alpha = 0.8
            addChild(background)
        }

        layoutReplayBox()
        layoutLetterRow()
    }

    private func layoutReplayBox() {
        let rect = replayBoxRect
        let root = SKNode()
        root.name = "replayBox"
        root.position = CGPoint(x: rect.midX, y: rect.midY)
        root.zPosition = 20

        let box = SKShapeNode(rectOf: rect.size, cornerRadius: 12)
        box.fillColor = replayFill
        box.strokeColor = UIColor(white: 0.65, alpha: 1)
        box.lineWidth = 2
        box.zPosition = 0
        root.addChild(box)

        let label = SKLabelNode(text: "♪")
        label.fontName = "Helvetica-Bold"
        label.fontSize = min(rect.height * 0.62, 34)
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        label.isUserInteractionEnabled = false
        root.addChild(label)

        replayBoxNode = root
        addChild(root)
    }

    private func rebuildLayout() {
        let matched = engine.matchedIDs
        buildPuzzle()
        for id in matched {
            applyMatchedAppearance(id: id)
        }
    }

    private func layoutLetterRow() {
        let tokens = engine.letters
        guard !tokens.isEmpty else { return }

        let layout = letterRowLayout(letterCount: tokens.count)
        laidOutTileSide = layout.side
        var x = layout.firstCenterX

        for token in tokens {
            let node = makeLetterNode(token: token, side: layout.side)
            node.position = CGPoint(x: x, y: layout.centerY)
            addChild(node)
            letterNodes[token.id] = node
            x += layout.side + layout.gap
        }
    }

    private func makeLetterNode(token: GateLetterMatchMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        let matched = engine.matchedIDs.contains(token.id)
        if let textures = switchTextures {
            let texture = matched ? textures.on : textures.off
            if let switchNode = GateLetterMatchSwitchSprites.sprite(texture: texture, side: side) {
                switchNode.zPosition = 0
                switchNode.name = "switch"
                root.addChild(switchNode)
                switchNodes[token.id] = switchNode
            }
        } else {
            let square = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: side * 0.12)
            square.fillColor = matched ? squareMatchedFill : squareFill
            square.strokeColor = UIColor(white: 0.25, alpha: 1)
            square.lineWidth = 2
            square.zPosition = 0
            square.name = "switchFallback"
            root.addChild(square)
        }

        let letter = makeOutlinedLetter(text: token.letter, fontSize: side * 0.378)
        letter.zPosition = 1
        letter.isUserInteractionEnabled = false
        root.addChild(letter)

        return root
    }

    /// White letter with black outline and a thin inner shadow for readability on the switch.
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
        // Slightly up-left so the fill covers most of it → thin inset shadow.
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

    // MARK: - Events

    private func handle(_ event: GateLetterMatchEngineEvent) {
        switch event {
        case .timerTick:
            SoundEffectsController.shared.play(event: "timer_tick", from: playerFx)
        case .playTargetPronunciation:
            playTargetPronunciation()
        case let .playName(trackID):
            SoundEffectsController.shared.play(trackID: trackID)
        case .playYay:
            playCorrectSound()
        case let .correctMatch(id):
            applyMatchedAppearance(id: id)
        case let .incorrectMatch(id, _):
            let nameTrackID = engine.letters.first { $0.id == id }?.nameTrackID
            runTapFeedback(
                events: [.incorrectMatch(id: id, pronunciationTrackID: "")],
                nameTrackID: nameTrackID,
                isCorrect: false,
                incorrectID: id
            )
        case .won:
            finishWon()
        case .lost:
            finishLost()
        }
    }

    /// Tap audio chain (each cue starts when the previous finishes):
    /// switch → tapped letter → correct/error → next/current target.
    private func handleTapEvents(_ events: [GateLetterMatchEngineEvent]) {
        let nameTrack = events.compactMap { event -> String? in
            if case let .playName(trackID) = event { return trackID }
            return nil
        }.first
        let isCorrect = events.contains(.playYay)
        let incorrectID = events.compactMap { event -> UUID? in
            if case let .incorrectMatch(id, _) = event { return id }
            return nil
        }.first

        if isCorrect {
            runTapFeedback(events: events, nameTrackID: nameTrack, isCorrect: true)
            return
        }

        if let incorrectID {
            for event in events {
                switch event {
                case .playName, .incorrectMatch:
                    break
                default:
                    handle(event)
                }
            }
            runTapFeedback(
                events: events,
                nameTrackID: nameTrack,
                isCorrect: false,
                incorrectID: incorrectID
            )
            return
        }

        for event in events {
            handle(event)
        }
    }

    private func runTapFeedback(
        events: [GateLetterMatchEngineEvent],
        nameTrackID: String?,
        isCorrect: Bool,
        incorrectID: UUID? = nil
    ) {
        inputLocked = true

        if isCorrect {
            for event in events {
                switch event {
                case .playName, .playYay, .playTargetPronunciation, .won:
                    break
                case let .correctMatch(id):
                    applyMatchedAppearance(id: id)
                default:
                    handle(event)
                }
            }
        }

        let playTargetPrompt = isCorrect
            ? events.contains(.playTargetPronunciation)
            : true
        let didWin = events.contains(.won)
        let feedbackTrackID = isCorrect ? correctSoundTrackID : errorSoundTrackID
        let feedbackDuration = SoundEffectsController.shared.cueDuration(of: feedbackTrackID)

        var audioSteps: [SKAction] = []
        appendTrackSteps(to: &audioSteps, trackID: nameTrackID)
        audioSteps.append(SKAction.run { [weak self] in
            if isCorrect {
                self?.playCorrectSound()
            } else {
                self?.playErrorSound()
            }
        })
        audioSteps.append(SKAction.wait(forDuration: feedbackDuration))
        if playTargetPrompt {
            audioSteps.append(SKAction.run { [weak self] in self?.playTargetPronunciation() })
        }

        let finish = SKAction.run { [weak self] in
            guard let self else { return }
            if didWin {
                self.finishWon()
            }
            self.inputLocked = false
        }

        if isCorrect {
            run(SKAction.sequence(audioSteps + [finish]))
            return
        }

        let flashTwice = wrongFlashAction(for: incorrectID)
        run(SKAction.sequence([
            SKAction.group([
                flashTwice,
                SKAction.sequence(audioSteps),
            ]),
            finish,
        ]))
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

    private func playTargetPronunciation() {
        let trackID = engine.targetPronunciationTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    private func appendTrackSteps(to steps: inout [SKAction], trackID: String?) {
        guard let trackID, !trackID.isEmpty else { return }
        let duration = SoundEffectsController.shared.cueDuration(of: trackID)
        steps.append(SKAction.run {
            SoundEffectsController.shared.play(trackID: trackID)
        })
        steps.append(SKAction.wait(forDuration: duration))
    }

    private func applyMatchedAppearance(id: UUID) {
        if let switchNode = switchNodes[id], let on = switchTextures?.on {
            let size = switchNode.size
            switchNode.texture = on
            switchNode.size = size
            switchNode.colorBlendFactor = 0
        } else if let square = letterNodes[id]?.childNode(withName: "switchFallback") as? SKShapeNode {
            square.fillColor = squareMatchedFill
        }
        letterNodes[id]?.alpha = 1
    }

    private func wrongFlashAction(for id: UUID?) -> SKAction {
        let switchNode = id.flatMap { switchNodes[$0] }
        let fallback = id.flatMap { letterNodes[$0]?.childNode(withName: "switchFallback") as? SKShapeNode }
        return SKAction.doubleFlash(
            apply: { [weak self] in
                if let switchNode {
                    switchNode.color = self?.squareWrongFill ?? .systemRed
                    switchNode.colorBlendFactor = 0.55
                } else {
                    fallback?.fillColor = self?.squareWrongFill ?? .systemRed
                }
            },
            clear: { [weak self] in
                if let switchNode {
                    switchNode.colorBlendFactor = 0
                } else {
                    fallback?.fillColor = self?.squareFill ?? .brown
                }
            }
        )
    }

    private func publishTimer() {
        let seconds = max(0, Int(ceil(engine.remainingTime - 1e-9)))
        letterMatchDelegate?.gateLetterMatchSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.playCommon(event: "win")
        if case let .won(stars) = engine.outcome {
            letterMatchDelegate?.gateLetterMatchSceneDidWin(starsAwarded: stars)
        } else {
            letterMatchDelegate?.gateLetterMatchSceneDidWin(starsAwarded: engine.letters.count)
        }
    }

    private func finishLost() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.playCommon(event: "lose")
        letterMatchDelegate?.gateLetterMatchSceneDidLose()
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !inputLocked, let touch = touches.first else { return }
        let location = touch.location(in: self)

        if replayBoxRect.contains(location) {
            playTargetPronunciation()
            flashReplayBox()
            return
        }

        guard let id = letterID(at: location),
              !engine.matchedIDs.contains(id) else { return }

        // switch → tapped letter → correct/error → next/current target (see handleTapEvents).
        SoundEffectsController.shared.play(event: "switch_push", from: puzzleConfig.fx)
        let events = engine.tapLetter(id: id)
        guard !events.isEmpty else { return }
        let pushDuration = SoundEffectsController.shared.cueDuration(
            of: puzzleConfig.fx.trackID(for: "switch_push")
        )
        inputLocked = true
        run(SKAction.sequence([
            SKAction.wait(forDuration: pushDuration),
            SKAction.run { [weak self] in
                self?.handleTapEvents(events)
            },
        ]))
    }

    private func flashReplayBox() {
        guard let box = replayBoxNode?.children.first as? SKShapeNode else { return }
        let highlight = SKAction.run { box.fillColor = UIColor(white: 0.42, alpha: 1) }
        let restore = SKAction.run { [weak self] in
            box.fillColor = self?.replayFill ?? UIColor(white: 0.28, alpha: 1)
        }
        box.run(SKAction.sequence([
            highlight,
            SKAction.wait(forDuration: 0.12),
            restore,
        ]))
    }

    private func letterID(at point: CGPoint) -> UUID? {
        let side = laidOutTileSide > 0 ? laidOutTileSide : preferredTileSize
        for (id, node) in letterNodes {
            let half = side * 0.5
            let bounds = CGRect(
                x: node.position.x - half,
                y: node.position.y - half,
                width: side,
                height: side
            )
            if bounds.contains(point) {
                return id
            }
        }
        return nil
    }
}
