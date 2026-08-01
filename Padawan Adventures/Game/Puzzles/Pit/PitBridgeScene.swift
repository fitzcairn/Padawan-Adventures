import SpriteKit
import UIKit

protocol PitBridgeSceneDelegate: AnyObject {
    func pitBridgeSceneDidUpdateWord(_ word: String)
    func pitBridgeSceneDidWin(starsAwarded: Int)
}

/// SpriteKit pit-bridge puzzle: side pads, dashed slots, draggable lettered floor tiles.
final class PitBridgeScene: SKScene {
    weak var bridgeDelegate: PitBridgeSceneDelegate?

    private let bridgeConfig: PitBridgeConfig
    private let pitFx: SoundEffectTable
    private let playerFx: SoundEffectTable
    private let floorTileSetLibrary: FloorTileSetLibrary
    private let isoConfig: IsometricConfig
    private let spriteLibrary: SpriteLibrary
    private let playerSpriteConfig: SpriteConfig?

    private var engine: PitBridgeMinigameEngine
    private let speaker = PhonicsSpeaker()
    private var placementRNG = SystemRandomNumberGenerator()

    private var playerNode: SKNode?
    private var playerSprite: AnimatedSpriteNode?
    private var playerFacingLeft = false
    private var trayNodes: [UUID: SKNode] = [:]
    private var placedTileNodes: [SKNode] = []
    private var slotBoxNode: SKShapeNode?
    private var draggedNode: SKNode?
    private var dragOffset: CGPoint = .zero
    private var dragStartPosition: CGPoint = .zero

    private var didSetup = false
    private var didEnd = false
    private var isJumping = false
    private var didRevealTrayForRound = false
    private var promptContinuationArmed = false

    private let padFill = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1)
    private let platformCorrectTint = UIColor(red: 0.20, green: 0.65, blue: 0.28, alpha: 1)
    private let platformWrongTint = UIColor.systemRed
    private let playerFill = UIColor.systemRed

    private static let jumpDuration: TimeInterval = 1.0
    private static let playerLibraryID = "player"
    private static let playerZ: CGFloat = 1_000
    private static let padsZ: CGFloat = 1
    private static let placedTilesZ: CGFloat = 5
    private static let slotBoxZ: CGFloat = 8
    private static let trayTilesZ: CGFloat = 10
    private static let draggedZ: CGFloat = 60
    private static let promptWatchdogSeconds: TimeInterval = 10
    private static let promptWatchdogKey = "pitBridgePromptWatchdog"
    private static let winSoundActionKey = "pitBridgeWinSound"
    private static let springBackDuration: TimeInterval = 0.18

    init(
        size: CGSize,
        bridgeConfig: PitBridgeConfig,
        pitFx: SoundEffectTable,
        playerFx: SoundEffectTable,
        floorTileSetLibrary: FloorTileSetLibrary,
        isoConfig: IsometricConfig,
        spriteLibrary: SpriteLibrary,
        playerSpriteConfig: SpriteConfig?
    ) {
        self.bridgeConfig = bridgeConfig
        self.pitFx = pitFx
        self.playerFx = playerFx
        self.floorTileSetLibrary = floorTileSetLibrary
        self.isoConfig = isoConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.engine = PitBridgeMinigameEngine(config: .init(from: bridgeConfig))
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

    private var geometry: PitBridgeGeometry {
        PitBridgeGeometry(
            sceneSize: size,
            padSize: PitArenaLayout.floorPadBounds(config: isoConfig).size,
            slotCount: max(engine.wordCount, 1)
        )
    }

    override func didMove(to view: SKView) {
        guard !didSetup else { return }
        didSetup = true
        engine.begin()
        GameLogger.step(.world, "pitBridge.buildArena") { buildArena() }
        beginRound()
    }

    override func willMove(from view: SKView) {
        GameLogger.mark(.world, "pitBridge.willMove teardown")
        speaker.cancel()
        removeAction(forKey: Self.promptWatchdogKey)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard didSetup, !didEnd else { return }
        guard size.width > 1, size.height > 1 else { return }
        guard oldSize != size else { return }
        repositionForNewSize()
    }

    // MARK: - Arena

    private func buildArena() {
        removeAllChildren()
        trayNodes = [:]
        placedTileNodes = []
        slotBoxNode = nil

        let geo = geometry
        addPad(rect: geo.leftPadRect, name: "leftPad")
        addPad(rect: geo.rightPadRect, name: "rightPad")
        addPlayer(at: CGPoint(x: geo.leftPadRect.midX, y: geo.leftPadRect.midY))
    }

    private func addPad(rect: CGRect, name: String) {
        let root = SKNode()
        root.name = name
        root.position = CGPoint(x: rect.midX, y: rect.midY)
        root.zPosition = Self.padsZ

        if let cluster = makeFloorPadCluster(
            library: floorTileSetLibrary,
            config: isoConfig,
            using: &placementRNG
        ) {
            root.addChild(cluster)
        } else {
            let fallback = SKShapeNode(rectOf: rect.size, cornerRadius: 6)
            fallback.fillColor = padFill
            fallback.strokeColor = UIColor(white: 0.2, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = 0
            root.addChild(fallback)
        }
        addChild(root)
    }

    private func addPlayer(at position: CGPoint) {
        playerSprite = nil
        playerFacingLeft = false
        let height = playerDisplayHeight

        if let config = playerSpriteConfig,
           spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_right") != nil
            || spriteLibrary.animation(id: Self.playerLibraryID, named: "idle_down") != nil {
            let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
            sprite.fitHeight(height)
            sprite.zPosition = Self.playerZ
            sprite.name = "player"
            sprite.position = position
            addChild(sprite)
            playerNode = sprite
            playerSprite = sprite
            let correction = height * CGFloat(config.anchorCorrection) / 100
            sprite.position = CGPoint(x: position.x, y: position.y - correction)
            resumePlayerIdle()
            return
        }

        let radius = max(height * 0.28, 12)
        let fallback = SKShapeNode(circleOfRadius: radius)
        fallback.fillColor = playerFill
        fallback.strokeColor = UIColor(white: 0.9, alpha: 1)
        fallback.lineWidth = 2
        fallback.position = position
        fallback.zPosition = Self.playerZ
        fallback.name = "player"
        addChild(fallback)
        playerNode = fallback
    }

    private var playerDisplayHeight: CGFloat {
        if let config = playerSpriteConfig {
            return max(
                PlaceholderFactory.spriteDisplayHeight(isoConfig: isoConfig, spriteConfig: config),
                48
            )
        }
        return max(geometry.tileSide * 1.2, 48)
    }

    private func resumePlayerIdle() {
        guard playerSprite != nil else { return }
        let preferred = playerFacingLeft ? "idle_left" : "idle_right"
        let name: String
        if spriteLibrary.animation(id: Self.playerLibraryID, named: preferred) != nil {
            name = preferred
        } else {
            name = "idle_down"
        }
        playPlayerLoop(name)
    }

    private func playPlayerLoop(_ name: String) {
        guard let playerSprite else { return }
        playerSprite.play(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
        playerSprite.fitHeight(playerDisplayHeight)
    }

    private func playJumpAnimation(toward target: CGPoint) {
        guard let playerSprite, let playerNode else { return }
        playerFacingLeft = target.x < playerNode.position.x - 0.5
        let name = playerFacingLeft ? "jump_left" : "jump_right"
        playerSprite.playOnce(name: name, library: spriteLibrary, libraryID: Self.playerLibraryID)
        playerSprite.fitHeight(playerDisplayHeight)
    }

    // MARK: - Round flow

    private func beginRound() {
        guard !didEnd else { return }
        bridgeDelegate?.pitBridgeSceneDidUpdateWord(engine.currentWord)
        clearTray()
        drawSlotBox(at: geometry.slotCenter(engine.roundIndex))
        isUserInteractionEnabled = false
        didRevealTrayForRound = false
        speakPrompt { [weak self] in
            self?.revealTray()
        }
    }

    private func speakPrompt(then continuation: @escaping () -> Void) {
        promptContinuationArmed = true
        removeAction(forKey: Self.promptWatchdogKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: Self.promptWatchdogSeconds),
                SKAction.run { [weak self] in
                    self?.completePromptContinuation(continuation)
                },
            ]),
            withKey: Self.promptWatchdogKey
        )
        speaker.speak(engine.promptPhrases) { [weak self] in
            self?.completePromptContinuation(continuation)
        }
    }

    private func completePromptContinuation(_ continuation: @escaping () -> Void) {
        guard promptContinuationArmed else { return }
        promptContinuationArmed = false
        removeAction(forKey: Self.promptWatchdogKey)
        continuation()
    }

    private func drawSlotBox(at center: CGPoint) {
        slotBoxNode?.removeFromParent()
        let side = geometry.tileSide
        let rect = CGRect(x: -side * 0.5, y: -side * 0.5, width: side, height: side)
        let path = CGPath(rect: rect, transform: nil)
        let dashed = path.copy(
            dashingWithPhase: 0,
            lengths: [6, 6]
        )
        let box = SKShapeNode(path: dashed)
        box.strokeColor = .white
        box.lineWidth = 1
        box.fillColor = .clear
        box.position = center
        box.zPosition = Self.slotBoxZ
        box.name = "slotBox"
        addChild(box)
        slotBoxNode = box
    }

    private func revealTray() {
        guard !didEnd, !didRevealTrayForRound else { return }
        didRevealTrayForRound = true
        let geo = geometry
        for (index, choice) in engine.choices.enumerated() {
            let node = makeChoiceNode(choice: choice, side: geo.tileSide)
            node.position = geo.trayCenter(index)
            node.alpha = 0
            addChild(node)
            trayNodes[choice.id] = node
            node.run(SKAction.fadeIn(withDuration: 0.2))
        }
        isUserInteractionEnabled = true
    }

    private func makeChoiceNode(choice: PitBridgeMinigameEngine.Choice, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "choice:\(choice.id.uuidString)"
        root.userData = [
            "id": choice.id.uuidString,
            "letter": choice.letter,
        ]
        root.zPosition = Self.trayTilesZ

        if let tile = makeFloorTileNode(
            library: floorTileSetLibrary,
            config: isoConfig,
            using: &placementRNG
        ) {
            // Scale the isometric floor tile roughly to `side` wide.
            let measured = tile.calculateAccumulatedFrame()
            if measured.width > 1 {
                let scale = side / measured.width
                tile.setScale(scale)
            }
            tile.zPosition = 0
            root.addChild(tile)
        } else {
            let fallback = SKShapeNode(rectOf: CGSize(width: side, height: side * 0.6), cornerRadius: 4)
            fallback.fillColor = UIColor(white: 0.22, alpha: 1)
            fallback.strokeColor = UIColor(white: 0.65, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = 0
            root.addChild(fallback)
        }

        let label = SKLabelNode(text: choice.letter)
        label.name = "letterLabel"
        label.fontName = AppFont.name
        label.fontSize = max(side * 0.55, 18)
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: side * 0.75)
        label.zPosition = 1
        label.isUserInteractionEnabled = false
        root.addChild(label)

        return root
    }

    private func clearTray() {
        for (_, node) in trayNodes {
            node.removeFromParent()
        }
        trayNodes = [:]
    }

    // MARK: - Touch / drag

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, !isJumping, isUserInteractionEnabled, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let node = choiceNode(at: location) else { return }
        guard node.action(forKey: "springBack") == nil else { return }
        draggedNode = node
        dragStartPosition = node.position
        dragOffset = CGPoint(x: node.position.x - location.x, y: node.position.y - location.y)
        node.zPosition = Self.draggedZ
        if let letter = node.userData?["letter"] as? String {
            speaker.speak([letter], completion: {})
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !didEnd, let touch = touches.first, let node = draggedNode else { return }
        let location = touch.location(in: self)
        var next = CGPoint(x: location.x + dragOffset.x, y: location.y + dragOffset.y)
        let half = geometry.tileSide * 0.5
        next.x = min(max(next.x, half), size.width - half)
        next.y = min(max(next.y, half), size.height - half)
        node.position = next
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endDrag()
    }

    private func endDrag() {
        guard let node = draggedNode else { return }
        draggedNode = nil
        guard let idString = node.userData?["id"] as? String,
              let id = UUID(uuidString: idString) else {
            node.zPosition = Self.trayTilesZ
            return
        }

        guard geometry.isDrop(node.position, onSlot: engine.roundIndex) else {
            node.zPosition = Self.trayTilesZ
            springBack(node, to: dragStartPosition)
            return
        }

        guard let result = engine.accept(choiceID: id) else {
            node.zPosition = Self.trayTilesZ
            springBack(node, to: dragStartPosition)
            return
        }

        isUserInteractionEnabled = false
        switch result {
        case let .correct(slotIndex, won):
            handleCorrectDrop(node: node, id: id, slotIndex: slotIndex, won: won)
        case .incorrect:
            handleIncorrectDrop(node: node)
        }
    }

    private func handleCorrectDrop(node: SKNode, id: UUID, slotIndex: Int, won: Bool) {
        let target = geometry.slotCenter(slotIndex)
        node.position = target
        flashOverlay(on: node, color: platformCorrectTint) { [weak self] in
            guard let self else { return }
            self.playDucked(
                event: "correct",
                from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
            )
            if let label = node.childNode(withName: "letterLabel") {
                label.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.3),
                    SKAction.removeFromParent(),
                ]))
            }
            self.slotBoxNode?.removeFromParent()
            self.slotBoxNode = nil
            node.zPosition = Self.placedTilesZ
            self.trayNodes.removeValue(forKey: id)
            self.placedTileNodes.append(node)
            let leftovers = Array(self.trayNodes.values)
            self.trayNodes = [:]
            for other in leftovers {
                other.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.2),
                    SKAction.removeFromParent(),
                ]))
            }
            self.isJumping = true
            self.jumpPlayer(to: target) {
                self.isJumping = false
                if won {
                    self.finishWon()
                } else {
                    self.beginRound()
                }
            }
        }
    }

    private func handleIncorrectDrop(node: SKNode) {
        flashOverlay(on: node, color: platformWrongTint) { [weak self] in
            guard let self else { return }
            self.playDucked(
                event: "error",
                from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
            )
            self.springBack(node, to: self.dragStartPosition) {
                self.speakPrompt {
                    self.isUserInteractionEnabled = true
                }
            }
        }
    }

    private func springBack(_ node: SKNode, to position: CGPoint, completion: (() -> Void)? = nil) {
        let action = SKAction.move(to: position, duration: Self.springBackDuration)
        action.timingMode = .easeOut
        node.run(
            .sequence([
                action,
                .run {
                    node.zPosition = Self.trayTilesZ
                    completion?()
                },
            ]),
            withKey: "springBack"
        )
    }

    private func flashOverlay(on node: SKNode, color: UIColor, completion: @escaping () -> Void) {
        let side = geometry.tileSide
        let overlay = SKShapeNode(rectOf: CGSize(width: side, height: side * 0.6), cornerRadius: 4)
        overlay.fillColor = color.withAlphaComponent(0.55)
        overlay.strokeColor = .clear
        overlay.zPosition = 50
        overlay.name = "flashOverlay"
        node.addChild(overlay)
        let flash = SKAction.doubleFlash(
            count: 1,
            apply: { overlay.alpha = 1 },
            clear: { overlay.alpha = 0 }
        )
        overlay.run(flash) {
            overlay.removeFromParent()
            completion()
        }
    }

    private func choiceNode(at point: CGPoint) -> SKNode? {
        let hits = nodes(at: point)
        for hit in hits {
            var current: SKNode? = hit
            while let node = current {
                if let name = node.name, name.hasPrefix("choice:") {
                    return node
                }
                current = node.parent
            }
        }
        return nil
    }

    // MARK: - Jump / win

    private func jumpPlayer(
        to target: CGPoint,
        landAnimation: String? = nil,
        completion: @escaping () -> Void
    ) {
        guard let playerNode else {
            completion()
            return
        }
        playDucked(event: "jump", from: pitFx)
        let start = playerNode.position
        playJumpAnimation(toward: target)
        let arcHeight = max(
            geometry.tileSide * 1.1,
            hypot(target.x - start.x, target.y - start.y) * 0.35
        )
        let control = CGPoint(
            x: (start.x + target.x) * 0.5,
            y: max(start.y, target.y) + arcHeight
        )
        let duration = Self.jumpDuration
        let action = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            guard let self, let playerNode = self.playerNode else { return }
            let t = min(max(elapsedTime / CGFloat(duration), 0), 1)
            playerNode.position = PitArenaLayout.jumpPoint(
                t: t,
                start: start,
                control: control,
                end: target
            )
        }
        playerNode.run(action) { [weak self] in
            guard let self, let playerNode = self.playerNode else {
                completion()
                return
            }
            playerNode.position = target
            if let landAnimation,
               self.spriteLibrary.animation(id: Self.playerLibraryID, named: landAnimation) != nil {
                self.playPlayerLoop(landAnimation)
            } else {
                self.resumePlayerIdle()
            }
            completion()
        }
    }

    private func finishWon() {
        guard !didEnd else { return }
        didEnd = true
        isUserInteractionEnabled = false
        let exit = CGPoint(x: geometry.rightPadRect.midX, y: geometry.rightPadRect.midY)
        isJumping = true
        jumpPlayer(to: exit, landAnimation: "celebrate_down") { [weak self] in
            guard let self else { return }
            self.isJumping = false
            let stars = self.engine.wordCount
            var actions: [SKAction] = []
            actions.append(SKAction.run { [weak self] in
                guard let self else { return }
                self.playDucked(
                    event: "win",
                    from: SoundEffectsController.shared.commonFx.merging(self.pitFx)
                )
            })
            actions.append(SKAction.run { [weak self] in
                self?.bridgeDelegate?.pitBridgeSceneDidWin(starsAwarded: stars)
            })
            self.run(SKAction.sequence(actions), withKey: Self.winSoundActionKey)
        }
    }

    // MARK: - Resize

    private func repositionForNewSize() {
        let geo = geometry
        if let left = childNode(withName: "leftPad") {
            left.position = CGPoint(x: geo.leftPadRect.midX, y: geo.leftPadRect.midY)
        }
        if let right = childNode(withName: "rightPad") {
            right.position = CGPoint(x: geo.rightPadRect.midX, y: geo.rightPadRect.midY)
        }
        for (index, node) in placedTileNodes.enumerated() {
            node.position = geo.slotCenter(index)
        }
        if let slotBoxNode {
            slotBoxNode.position = geo.slotCenter(engine.roundIndex)
        }
        let trayChoices = engine.choices
        for (index, choice) in trayChoices.enumerated() {
            trayNodes[choice.id]?.position = geo.trayCenter(index)
        }
        if !isJumping, placedTileNodes.isEmpty, let playerNode {
            playerNode.position = CGPoint(x: geo.leftPadRect.midX, y: geo.leftPadRect.midY)
        } else if !isJumping, let last = placedTileNodes.last, let playerNode {
            playerNode.position = last.position
        }
    }

    // MARK: - Audio

    private func playDucked(event: String, from table: SoundEffectTable) {
        guard let trackID = table.trackID(for: event) else { return }
        SoundEffectsController.shared.play(trackID: trackID)
        BackgroundMusicController.shared.duckForPhoneticCue(
            duration: SoundEffectsController.shared.cueDuration(of: trackID)
        )
    }
}
