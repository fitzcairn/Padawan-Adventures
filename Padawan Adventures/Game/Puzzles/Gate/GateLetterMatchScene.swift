import AVFoundation
import SpriteKit
import UIKit

protocol GateLetterMatchSceneDelegate: AnyObject {
    func gateLetterMatchSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func gateLetterMatchSceneDidWin(starsAwarded: Int)
    func gateLetterMatchSceneDidLose()
}

/// SpriteKit gate letter-match puzzle: staging area, tappable letter tiles, timer-driven engine.
final class GateLetterMatchScene: SKScene {
    weak var letterMatchDelegate: GateLetterMatchSceneDelegate?

    private let puzzleConfig: GateLetterMatchConfig
    private let playerFx: SoundEffectTable

    private var engine: GateLetterMatchMinigameEngine
    private var stagingNode: SKShapeNode!
    private var replayBoxNode: SKNode!
    private var letterNodes: [UUID: SKNode] = [:]
    private var squareNodes: [UUID: SKShapeNode] = [:]
    private var didEnd = false
    private var didSetup = false
    private var inputLocked = false
    private var lastUpdateTime: TimeInterval?

    private let stagingFill = UIColor(white: 0.45, alpha: 1)
    private let replayFill = UIColor(white: 0.28, alpha: 1)
    private let squareFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    private let squareMatchedFill = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    private let squareWrongFill = UIColor.systemRed

    private let letterSpriteSetLibrary: LetterSpriteSetLibrary

    init(
        size: CGSize,
        puzzleConfig: GateLetterMatchConfig,
        playerFx: SoundEffectTable,
        letterSpriteSetLibrary: LetterSpriteSetLibrary
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.letterSpriteSetLibrary = letterSpriteSetLibrary
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

    private var tileSize: CGFloat {
        let count = max(engine.letters.count, 1)
        let rect = stagingRect
        let maxByWidth = (rect.width * 0.9) / CGFloat(count) * 0.85
        let maxByHeight = rect.height * 0.55
        return min(maxByWidth, maxByHeight, min(size.width, size.height) * 0.18)
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
        squareNodes = [:]

        let rect = stagingRect
        stagingNode = SKShapeNode(rectOf: rect.size, cornerRadius: 10)
        stagingNode.fillColor = stagingFill
        stagingNode.strokeColor = UIColor(white: 0.55, alpha: 1)
        stagingNode.lineWidth = 2
        stagingNode.position = CGPoint(x: rect.midX, y: rect.midY)
        stagingNode.zPosition = 1
        stagingNode.name = "staging"
        addChild(stagingNode)

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

        let side = tileSize
        let gap = side * 0.18
        let totalWidth = CGFloat(tokens.count) * side + CGFloat(tokens.count - 1) * gap
        let rect = stagingRect
        var x = rect.midX - totalWidth * 0.5 + side * 0.5
        let y = rect.midY

        for token in tokens {
            let node = makeLetterNode(token: token, side: side)
            node.position = CGPoint(x: x, y: y)
            addChild(node)
            letterNodes[token.id] = node
            x += side + gap
        }
    }

    private func makeLetterNode(token: GateLetterMatchMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        let square = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: side * 0.12)
        square.fillColor = squareFill
        square.strokeColor = UIColor(white: 0.25, alpha: 1)
        square.lineWidth = 2
        square.zPosition = 0
        root.addChild(square)
        squareNodes[token.id] = square

        if let glyph = LetterSpriteFactory.sprite(
            letter: token.letter,
            side: side * 0.62,
            library: letterSpriteSetLibrary
        ) {
            glyph.zPosition = 1
            glyph.isUserInteractionEnabled = false
            root.addChild(glyph)
        } else {
            let label = SKLabelNode(text: token.letter)
            label.fontName = "Helvetica-Bold"
            label.fontSize = side * 0.62
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 1
            label.isUserInteractionEnabled = false
            root.addChild(label)
        }

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
        case let .incorrectMatch(id, pronunciationTrackID):
            runIncorrectFeedback(id: id, pronunciationTrackID: pronunciationTrackID)
        case .won:
            finishWon()
        case .lost:
            finishLost()
        }
    }

    /// Processes letter-tap events; sequences name → correct (and follow-ups) so they don't overlap.
    private func handleTapEvents(_ events: [GateLetterMatchEngineEvent]) {
        let nameTrack = events.compactMap { event -> String? in
            if case let .playName(trackID) = event { return trackID }
            return nil
        }.first
        let isCorrect = events.contains(.playYay)

        if isCorrect {
            runCorrectFeedback(events: events, nameTrackID: nameTrack)
            return
        }

        for event in events {
            handle(event)
        }
    }

    private func runCorrectFeedback(
        events: [GateLetterMatchEngineEvent],
        nameTrackID: String?
    ) {
        inputLocked = true

        for event in events {
            switch event {
            case let .playName(trackID):
                SoundEffectsController.shared.play(trackID: trackID)
            case let .correctMatch(id):
                applyMatchedAppearance(id: id)
            case .playYay, .playTargetPronunciation, .won:
                break
            default:
                handle(event)
            }
        }

        let playNextPrompt = events.contains(.playTargetPronunciation)
        let didWin = events.contains(.won)
        let nameDuration = audioDuration(for: nameTrackID)
        let correctDuration = audioDuration(for: correctSoundTrackID)
        /// Beat between “correct” feedback and the next target pronunciation.
        let nextLetterPause: TimeInterval = 0.45

        var steps: [SKAction] = [
            SKAction.wait(forDuration: nameDuration),
            SKAction.run { [weak self] in self?.playCorrectSound() },
            SKAction.wait(forDuration: correctDuration),
        ]
        if playNextPrompt {
            steps.append(SKAction.wait(forDuration: nextLetterPause))
            steps.append(SKAction.run { [weak self] in self?.playTargetPronunciation() })
        }
        steps.append(SKAction.run { [weak self] in
            guard let self else { return }
            if didWin {
                self.finishWon()
            }
            self.inputLocked = false
        })
        run(SKAction.sequence(steps))
    }

    private var correctSoundTrackID: String? {
        SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx).trackID(for: "correct")
    }

    private func playCorrectSound() {
        SoundEffectsController.shared.play(
            event: "correct",
            from: SoundEffectsController.shared.commonFx.merging(puzzleConfig.fx)
        )
    }

    private func playTargetPronunciation() {
        let trackID = engine.targetPronunciationTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    private func applyMatchedAppearance(id: UUID) {
        squareNodes[id]?.fillColor = squareMatchedFill
        letterNodes[id]?.alpha = 1
    }

    private func runIncorrectFeedback(id: UUID, pronunciationTrackID: String) {
        inputLocked = true
        let square = squareNodes[id]
        let nameDuration = audioDuration(for: engine.letters.first { $0.id == id }?.nameTrackID)
        let waitName = SKAction.wait(forDuration: nameDuration)
        let flashOn = SKAction.run { [weak self] in
            square?.fillColor = self?.squareWrongFill ?? .systemRed
        }
        let flashOff = SKAction.run { [weak self] in
            square?.fillColor = self?.squareFill ?? .brown
        }
        let flash = SKAction.sequence([
            flashOn,
            SKAction.wait(forDuration: 0.12),
            flashOff,
            SKAction.wait(forDuration: 0.12),
        ])
        let flashTwice = SKAction.repeat(flash, count: 2)
        let playWrongPronunciation = SKAction.run {
            SoundEffectsController.shared.play(trackID: pronunciationTrackID)
        }
        let unlock = SKAction.run { [weak self] in
            self?.inputLocked = false
        }
        run(SKAction.sequence([waitName, flashTwice, playWrongPronunciation, unlock]))
    }

    private func audioDuration(for trackID: String?) -> TimeInterval {
        guard let trackID, !trackID.isEmpty,
              let url = BundleMusicAudioPlayer.audioURL(
                for: trackID,
                subdirectories: ["Audio/FX", "Audio"]
              ),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return 0.7
        }
        return max(player.duration, 0.35)
    }

    private func publishTimer() {
        let seconds = max(0, Int(ceil(engine.remainingTime - 1e-9)))
        letterMatchDelegate?.gateLetterMatchSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
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

        let events = engine.tapLetter(id: id)
        handleTapEvents(events)
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
        let side = tileSize
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
