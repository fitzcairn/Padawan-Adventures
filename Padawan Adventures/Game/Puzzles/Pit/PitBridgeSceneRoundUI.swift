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
