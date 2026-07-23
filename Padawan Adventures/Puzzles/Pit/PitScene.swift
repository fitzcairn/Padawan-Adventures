import AVFoundation
import SpriteKit
import UIKit

protocol PitSceneDelegate: AnyObject {
    func pitSceneDidUpdateTimer(seconds: Int, urgent: Bool)
    func pitSceneDidSelectWord(_ word: String)
    func pitSceneDidUpdateSolvedCount(_ count: Int)
    func pitSceneDidWin(word: String, starsAwarded: Int)
    func pitSceneDidLose()
}

/// SpriteKit pit puzzle: side pads, hoppable letter circles, timer-driven engine.
final class PitScene: SKScene {
    weak var pitDelegate: PitSceneDelegate?

    private let puzzleConfig: PitPuzzleConfig
    private let playerFx: SoundEffectTable

    private var engine: PitMinigameEngine
    private var letterNodes: [UUID: SKNode] = [:]
    private var circleNodes: [UUID: SKShapeNode] = [:]
    private var playerNode: SKShapeNode!
    private var leftPadRect: CGRect = .zero
    private var rightPadRect: CGRect = .zero
    private var playFieldRect: CGRect = .zero
    private var didEnd = false
    private var didSetup = false
    private var isJumping = false
    private var lastUpdateTime: TimeInterval?
    private var placementRNG = SystemRandomNumberGenerator()

    private let padFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    private let circleFill = UIColor(white: 0.22, alpha: 1)
    private let circleCorrectFill = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    private let circleWrongFlash = UIColor.systemYellow
    private let playerFill = UIColor.systemRed

    private static let jumpDuration: TimeInterval = 1.0
    private static let connectedSoundActionKey = "pitConnectedSound"
    private static let winSoundActionKey = "pitWinSound"

    init(
        size: CGSize,
        puzzleConfig: PitPuzzleConfig,
        playerFx: SoundEffectTable
    ) {
        self.puzzleConfig = puzzleConfig
        self.playerFx = playerFx
        self.engine = PitMinigameEngine(config: .init(from: puzzleConfig))
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
        pitDelegate?.pitSceneDidSelectWord(engine.targetWord)
        pitDelegate?.pitSceneDidUpdateSolvedCount(0)
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

    private var letterRadius: CGFloat {
        min(size.width, size.height) * 0.055
    }

    /// Jump reach: at least enough to clear one equal-width word band plus vertical slack.
    private var maxJumpDistance: CGFloat {
        let bands = max(engine.wordLetterIDs.count, 1)
        let bandWidth = playFieldRect.width / CGFloat(bands)
        let bandReach = hypot(bandWidth * 1.2, playFieldRect.height * 0.55)
        return max(letterRadius * 5.5, bandReach)
    }

    private var minPadding: CGFloat {
        letterRadius * 0.35
    }

    private func computeLayoutFrames() {
        let padHeight = size.height * 0.60
        let padWidth = padHeight / 3.0
        let padY = (size.height - padHeight) * 0.5
        leftPadRect = CGRect(x: 0, y: padY, width: padWidth, height: padHeight)
        rightPadRect = CGRect(
            x: size.width - padWidth,
            y: padY,
            width: padWidth,
            height: padHeight
        )
        let fieldInset = letterRadius + minPadding
        playFieldRect = CGRect(
            x: leftPadRect.maxX + fieldInset,
            y: fieldInset,
            width: max(rightPadRect.minX - leftPadRect.maxX - fieldInset * 2, letterRadius * 2),
            height: max(size.height - fieldInset * 2, letterRadius * 2)
        )
    }

    private func buildPuzzle() {
        removeAllChildren()
        letterNodes = [:]
        circleNodes = [:]
        computeLayoutFrames()

        addPad(rect: leftPadRect, name: "leftPad")
        addPad(rect: rightPadRect, name: "rightPad")

        let radius = letterRadius
        var placedCenters: [CGPoint] = []

        // Place word letters in equal-width horizontal bands across the play field.
        let startAnchor = CGPoint(x: leftPadRect.midX, y: leftPadRect.midY)
        var previous = startAnchor
        let wordCount = engine.wordLetterIDs.count
        for (index, id) in engine.wordLetterIDs.enumerated() {
            guard let token = engine.letter(id: id) else { continue }
            let position = placeWordLetter(
                index: index,
                count: wordCount,
                near: previous,
                radius: radius,
                avoiding: placedCenters
            )
            let node = makeLetterNode(token: token, radius: radius)
            node.position = position
            addChild(node)
            letterNodes[token.id] = node
            placedCenters.append(position)
            previous = position
        }

        // Place decoys in remaining play-field space.
        let wordIDs = Set(engine.wordLetterIDs)
        for token in engine.letters where !wordIDs.contains(token.id) {
            let position = placeDecoy(radius: radius, avoiding: placedCenters)
            let node = makeLetterNode(token: token, radius: radius)
            node.position = position
            addChild(node)
            letterNodes[token.id] = node
            placedCenters.append(position)
        }

        let playerRadius = letterRadius * 0.85
        playerNode = SKShapeNode(circleOfRadius: playerRadius)
        playerNode.fillColor = playerFill
        playerNode.strokeColor = UIColor(white: 0.9, alpha: 1)
        playerNode.lineWidth = 2
        playerNode.position = startAnchor
        playerNode.zPosition = 40
        playerNode.name = "player"
        addChild(playerNode)
    }

    private func rebuildLayoutPreservingLetters() {
        let previousPositions = letterNodes.mapValues(\.position)
        let previousPlayer = playerNode?.position
        buildPuzzle()
        let radius = letterRadius
        var placedCenters: [CGPoint] = []
        for id in engine.wordLetterIDs + engine.letters.map(\.id).filter({ !engine.wordLetterIDs.contains($0) }) {
            guard let node = letterNodes[id] else { continue }
            if let previous = previousPositions[id],
               isValidLetterPosition(previous, radius: radius, avoiding: placedCenters) {
                node.position = previous
                placedCenters.append(previous)
            }
        }
        if let previousPlayer {
            playerNode.position = previousPlayer
        }
    }

    private func addPad(rect: CGRect, name: String) {
        let node = SKShapeNode(rectOf: rect.size, cornerRadius: 6)
        node.fillColor = padFill
        node.strokeColor = UIColor(white: 0.2, alpha: 1)
        node.lineWidth = 2
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        node.zPosition = 1
        node.name = name
        addChild(node)
    }

    private func makeLetterNode(token: PitMinigameEngine.LetterToken, radius: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = engine.isSpent(token.id) ? circleCorrectFill : circleFill
        circle.strokeColor = UIColor(white: 0.65, alpha: 1)
        circle.lineWidth = 2
        circle.zPosition = 0
        root.addChild(circle)
        circleNodes[token.id] = circle

        let label = SKLabelNode(text: token.letter)
        label.fontName = "Helvetica-Bold"
        label.fontSize = radius * 1.35
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        label.isUserInteractionEnabled = false
        root.addChild(label)

        return root
    }

    private func minCenterDistance(for radius: CGFloat) -> CGFloat {
        radius * 2 + minPadding
    }

    /// Samples a word-letter center inside the `index`-th equal-width horizontal band
    /// spanning the play field between the side pads (`count` = word length).
    private func placeWordLetter(
        index: Int,
        count: Int,
        near previous: CGPoint,
        radius: CGFloat,
        avoiding occupied: [CGPoint]
    ) -> CGPoint {
        let bands = max(count, 1)
        let bandWidth = playFieldRect.width / CGFloat(bands)
        let bandMinX = playFieldRect.minX + CGFloat(index) * bandWidth
        let bandMaxX = bandMinX + bandWidth

        let minY = playFieldRect.minY + radius
        let maxY = playFieldRect.maxY - radius
        guard minY <= maxY else {
            return CGPoint(x: (bandMinX + bandMaxX) * 0.5, y: playFieldRect.midY)
        }

        let insetMinX = bandMinX + radius
        let insetMaxX = bandMaxX - radius
        let xRange: ClosedRange<CGFloat>
        if insetMinX <= insetMaxX {
            xRange = insetMinX...insetMaxX
        } else {
            let midX = (bandMinX + bandMaxX) * 0.5
            xRange = midX...midX
        }
        let yRange = minY...maxY
        let maxDist = maxJumpDistance

        for _ in 0..<160 {
            let point = CGPoint(
                x: CGFloat.random(in: xRange, using: &placementRNG),
                y: CGFloat.random(in: yRange, using: &placementRNG)
            )
            if isValidLetterPosition(point, radius: radius, avoiding: occupied),
               hypot(point.x - previous.x, point.y - previous.y) <= maxDist + 0.5 {
                return point
            }
        }

        // Prefer band center; still require non-overlap when possible.
        for _ in 0..<40 {
            let point = CGPoint(
                x: (bandMinX + bandMaxX) * 0.5,
                y: CGFloat.random(in: yRange, using: &placementRNG)
            )
            if isValidLetterPosition(point, radius: radius, avoiding: occupied) {
                return point
            }
        }

        return CGPoint(x: (bandMinX + bandMaxX) * 0.5, y: playFieldRect.midY)
    }

    private func placeDecoy(radius: CGFloat, avoiding occupied: [CGPoint]) -> CGPoint {
        let bounds = playFieldRect.insetBy(dx: radius, dy: radius)
        guard bounds.width > 0, bounds.height > 0 else {
            return CGPoint(x: playFieldRect.midX, y: playFieldRect.midY)
        }

        for _ in 0..<120 {
            let point = CGPoint(
                x: CGFloat.random(in: bounds.minX...bounds.maxX, using: &placementRNG),
                y: CGFloat.random(in: bounds.minY...bounds.maxY, using: &placementRNG)
            )
            if isValidLetterPosition(point, radius: radius, avoiding: occupied) {
                return point
            }
        }

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
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private func isValidLetterPosition(
        _ point: CGPoint,
        radius: CGFloat,
        avoiding occupied: [CGPoint]
    ) -> Bool {
        let letterBounds = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        guard playFieldRect.contains(letterBounds) else { return false }
        guard !letterBounds.intersects(leftPadRect.insetBy(dx: -2, dy: -2)),
              !letterBounds.intersects(rightPadRect.insetBy(dx: -2, dy: -2)) else {
            return false
        }

        let minDistance = minCenterDistance(for: radius)
        for other in occupied {
            if hypot(other.x - point.x, other.y - point.y) < minDistance {
                return false
            }
        }
        return true
    }

    // MARK: - Events / audio

    private func handle(_ event: PitEngineEvent) {
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

    /// Progressive prefix cue only — word sound is reserved for incorrect jumps / open / win.
    private func playConnectedPrefixSound(_ prefix: String, then completion: (() -> Void)? = nil) {
        removeAction(forKey: Self.connectedSoundActionKey)
        guard !prefix.isEmpty else {
            completion?()
            return
        }

        let progressiveID = engine.targetEntry.progressiveTrack(forPrefix: prefix)
        var actions: [SKAction] = []
        if let progressiveID, !progressiveID.isEmpty {
            actions.append(SKAction.run {
                SoundEffectsController.shared.play(trackID: progressiveID)
            })
            actions.append(SKAction.wait(forDuration: audioDuration(for: progressiveID)))
        }
        if let completion {
            actions.append(SKAction.run(completion))
        }
        guard !actions.isEmpty else {
            completion?()
            return
        }
        run(SKAction.sequence(actions), withKey: Self.connectedSoundActionKey)
    }

    private func audioDuration(for trackID: String) -> TimeInterval {
        guard let url = BundleMusicAudioPlayer.audioURL(
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
        pitDelegate?.pitSceneDidUpdateTimer(seconds: seconds, urgent: seconds <= 5)
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false

        let spellingID = engine.targetSoundTrackID
        var actions: [SKAction] = []
        if !spellingID.isEmpty {
            actions.append(SKAction.run {
                SoundEffectsController.shared.play(trackID: spellingID)
            })
            actions.append(SKAction.wait(forDuration: audioDuration(for: spellingID)))
        }
        actions.append(SKAction.run { [weak self] in
            SoundEffectsController.shared.playCommon(
                event: "win",
                override: self?.puzzleConfig.winSound
            )
        })
        let word = engine.targetWord
        let stars = engine.targetWord.count
        actions.append(SKAction.run { [weak self] in
            self?.pitDelegate?.pitSceneDidWin(word: word, starsAwarded: stars)
        })
        run(SKAction.sequence(actions), withKey: Self.winSoundActionKey)
    }

    private func finishLost() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        SoundEffectsController.shared.playCommon(event: "lose", override: puzzleConfig.failSound)
        pitDelegate?.pitSceneDidLose()
    }

    // MARK: - Touch / jump

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isJumping, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let node = letterNode(at: location),
              let idString = node.userData?["id"] as? String,
              let id = UUID(uuidString: idString) else {
            return
        }
        guard !engine.isSpent(id) else { return }

        let distance = hypot(node.position.x - playerNode.position.x, node.position.y - playerNode.position.y)
        guard distance <= maxJumpDistance + 0.5 else { return }

        guard let result = engine.acceptLetter(id: id) else { return }
        let origin = playerNode.position
        isJumping = true

        switch result {
        case let .correct(prefix, won):
            jumpPlayer(to: node.position) { [weak self] in
                guard let self else { return }
                self.circleNodes[id]?.fillColor = self.circleCorrectFill
                self.pitDelegate?.pitSceneDidUpdateSolvedCount(prefix.count)
                self.playConnectedPrefixSound(prefix) {
                    if won {
                        let exit = CGPoint(x: self.rightPadRect.midX, y: self.rightPadRect.midY)
                        self.jumpPlayer(to: exit) {
                            self.isJumping = false
                            self.finishWon()
                        }
                    } else {
                        self.isJumping = false
                    }
                }
            }
        case .incorrect:
            jumpPlayer(to: node.position) { [weak self] in
                guard let self else { return }
                self.flashWrong(id: id) {
                    self.jumpPlayer(to: origin) {
                        self.playWordSound()
                        self.isJumping = false
                    }
                }
            }
        }
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

    private func jumpPlayer(to target: CGPoint, completion: @escaping () -> Void) {
        let start = playerNode.position
        let arcHeight = max(letterRadius * 2.2, hypot(target.x - start.x, target.y - start.y) * 0.35)
        let control = CGPoint(
            x: (start.x + target.x) * 0.5,
            y: max(start.y, target.y) + arcHeight
        )
        let duration = Self.jumpDuration
        let action = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            guard let self else { return }
            let linearT = min(max(elapsedTime / CGFloat(duration), 0), 1)
            // Smoothstep ease-in / ease-out.
            let t = linearT * linearT * (3 - 2 * linearT)
            let oneMinus = 1 - t
            let x = oneMinus * oneMinus * start.x + 2 * oneMinus * t * control.x + t * t * target.x
            let y = oneMinus * oneMinus * start.y + 2 * oneMinus * t * control.y + t * t * target.y
            self.playerNode.position = CGPoint(x: x, y: y)
        }
        playerNode.run(action) {
            self.playerNode.position = target
            completion()
        }
    }

    private func flashWrong(id: UUID, completion: @escaping () -> Void) {
        guard let circle = circleNodes[id] else {
            completion()
            return
        }
        let original = circleFill
        let flash = SKAction.sequence([
            SKAction.run { circle.fillColor = self.circleWrongFlash },
            SKAction.wait(forDuration: 0.12),
            SKAction.run { circle.fillColor = original },
            SKAction.wait(forDuration: 0.12),
            SKAction.run { circle.fillColor = self.circleWrongFlash },
            SKAction.wait(forDuration: 0.12),
            SKAction.run { circle.fillColor = original },
        ])
        circle.run(flash, completion: completion)
    }
}
