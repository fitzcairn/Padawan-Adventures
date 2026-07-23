import AVFoundation
import SpriteKit
import UIKit

protocol DestructibleWallSceneDelegate: AnyObject {
    func destructibleWallSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func destructibleWallSceneDidWin(starsAwarded: Int)
    func destructibleWallSceneDidLose()
}

/// SpriteKit wall puzzle: staging area, tappable letter tiles, timer-driven engine.
final class DestructibleWallScene: SKScene {
    weak var wallDelegate: DestructibleWallSceneDelegate?

    private let puzzleConfig: DestructibleWallPuzzleConfig
    private let playerFx: SoundEffectTable

    private var engine: DestructibleWallMinigameEngine
    private var stagingNode: SKShapeNode!
    private var letterNodes: [UUID: SKNode] = [:]
    private var squareNodes: [UUID: SKShapeNode] = [:]
    private var didEnd = false
    private var didSetup = false
    private var inputLocked = false
    private var lastUpdateTime: TimeInterval?

    private let stagingFill = UIColor(white: 0.45, alpha: 1)
    private let squareFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    private let squareMatchedFill = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    private let squareWrongFill = UIColor.systemRed

    init(
        size: CGSize,
        puzzleConfig: DestructibleWallPuzzleConfig,
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.engine = DestructibleWallMinigameEngine(config: .init(from: puzzleConfig))
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

        layoutLetterRow()
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

    private func makeLetterNode(token: DestructibleWallMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
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

        let label = SKLabelNode(text: token.letter)
        label.fontName = "Helvetica-Bold"
        label.fontSize = side * 0.62
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        label.isUserInteractionEnabled = false
        root.addChild(label)

        return root
    }

    // MARK: - Events

    private func handle(_ event: DestructibleWallEngineEvent) {
        switch event {
        case .timerTick:
            SoundEffectsController.shared.play(event: "timer_tick", from: playerFx)
        case .playTargetPronunciation:
            playTargetPronunciation()
        case let .playName(trackID):
            SoundEffectsController.shared.play(trackID: trackID)
        case .playYay:
            SoundEffectsController.shared.playCommon(
                event: "correct",
                override: puzzleConfig.correctSound
            )
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

    private func playTargetPronunciation() {
        let trackID = engine.targetPronunciationTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
        engine.markTargetSoundPlayed()
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
        wallDelegate?.destructibleWallSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        if case let .won(stars) = engine.outcome {
            wallDelegate?.destructibleWallSceneDidWin(starsAwarded: stars)
        } else {
            wallDelegate?.destructibleWallSceneDidWin(starsAwarded: engine.letters.count)
        }
    }

    private func finishLost() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        wallDelegate?.destructibleWallSceneDidLose()
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !inputLocked, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let id = letterID(at: location),
              !engine.matchedIDs.contains(id) else { return }

        let events = engine.tapLetter(id: id)
        for event in events {
            handle(event)
        }
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
