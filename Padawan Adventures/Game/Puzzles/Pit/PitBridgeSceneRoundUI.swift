import SpriteKit
import UIKit

extension PitBridgeScene {
    // MARK: - Round flow

    func beginRound() {
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

    func speakPrompt(then continuation: @escaping () -> Void) {
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

    func completePromptContinuation(_ continuation: @escaping () -> Void) {
        guard promptContinuationArmed else { return }
        promptContinuationArmed = false
        removeAction(forKey: Self.promptWatchdogKey)
        continuation()
    }

    func drawSlotBox(at center: CGPoint) {
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

    func revealTray() {
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

    func makeChoiceNode(choice: PitBridgeMinigameEngine.Choice, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "choice:\(choice.id.uuidString)"
        root.userData = [
            "id": choice.id.uuidString,
            "letter": choice.letter,
        ]
        root.zPosition = Self.trayTilesZ

        // Root origin == Kam feet on land. Shift the floor tile so its visual middle
        // sits on that point (north-tip anchor alone would land the tip under the feet).
        if let tile = makeFloorTileNode(
            library: floorTileSetLibrary,
            config: isoConfig,
            using: &placementRNG
        ) {
            let measured = tile.calculateAccumulatedFrame()
            if measured.width > 1 {
                tile.setScale(side / measured.width)
            }
            let bounds = tile.calculateAccumulatedFrame()
            tile.position = CGPoint(x: -bounds.midX, y: -bounds.midY)
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

        let label = OutlinedLetterFactory.make(
            text: choice.letter,
            fontSize: max(side * 0.55, 18),
            disablesInteraction: true
        )
        label.name = "letterLabel"
        // On the centered tile face (root origin).
        label.position = .zero
        label.zPosition = 1
        root.addChild(label)

        return root
    }

    func clearTray() {
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
        startForceLiftSparkles(on: node)
        playForceLiftAnimation(toward: node.position)
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

    func endDrag() {
        guard let node = draggedNode else { return }
        draggedNode = nil
        stopForceLiftSparkles(on: node)
        guard let idString = node.userData?["id"] as? String,
              let id = UUID(uuidString: idString) else {
            node.zPosition = Self.trayTilesZ
            resumePlayerIdle()
            return
        }

        guard geometry.isDrop(node.position, onSlot: engine.roundIndex) else {
            node.zPosition = Self.trayTilesZ
            resumePlayerIdle()
            springBack(node, to: dragStartPosition)
            return
        }

        guard let result = engine.accept(choiceID: id) else {
            node.zPosition = Self.trayTilesZ
            resumePlayerIdle()
            springBack(node, to: dragStartPosition)
            return
        }

        isUserInteractionEnabled = false
        switch result {
        case let .correct(slotIndex, won):
            // Jump clip replaces the Force-lift pose once the tile snaps into the slot.
            handleCorrectDrop(node: node, id: id, slotIndex: slotIndex, won: won)
        case .incorrect:
            resumePlayerIdle()
            handleIncorrectDrop(node: node)
        }
    }

    /// Blue + white Force sparkles while a tray tile is held.
    func startForceLiftSparkles(on node: SKNode) {
        node.removeAction(forKey: Self.forceLiftSparkleCleanupKey)
        for case let emitter as SKEmitterNode in node.children
        where emitter.name == SparkleEmitterFactory.nodeName {
            emitter.removeFromParent()
        }
        let height = geometry.tileSide
        for config in [HighlightConfig.forceLiftBlue, HighlightConfig.forceLiftWhite] {
            let glow = SparkleEmitterFactory.makeNode(config: config, referenceHeight: height)
            glow.zPosition = -1
            node.insertChild(glow, at: 0)
        }
    }

    /// Stops spawning so existing sparkles fade out after release / place.
    func stopForceLiftSparkles(on node: SKNode) {
        SparkleEmitterFactory.stop(in: node)
        let linger = max(
            HighlightConfig.forceLiftBlue.lifetime,
            HighlightConfig.forceLiftWhite.lifetime
        )
        node.removeAction(forKey: Self.forceLiftSparkleCleanupKey)
        node.run(
            .sequence([
                .wait(forDuration: linger),
                .run {
                    for case let emitter as SKEmitterNode in node.children
                    where emitter.name == SparkleEmitterFactory.nodeName {
                        emitter.removeFromParent()
                    }
                },
            ]),
            withKey: Self.forceLiftSparkleCleanupKey
        )
    }
    func choiceNode(at point: CGPoint) -> SKNode? {
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
}
