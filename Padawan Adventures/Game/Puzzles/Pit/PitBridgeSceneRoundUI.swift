import SpriteKit
import UIKit

extension PitBridgeScene {
    // MARK: - Round flow

    func beginRound() {
        guard !didEnd else { return }
        clearTray()
        showWordPrompt()
        drawSlotBox(at: geometry.slotCenter(engine.roundIndex))
        isUserInteractionEnabled = false
        didRevealTrayForRound = false
        playWordSound { [weak self] in
            self?.revealTray()
        }
    }

    /// Plays the current catalog word track, then continues (with a watchdog).
    func playWordSound(then continuation: @escaping () -> Void) {
        promptContinuationArmed = true
        removeAction(forKey: Self.promptWatchdogKey)
        removeAction(forKey: Self.promptSoundKey)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: Self.promptWatchdogSeconds),
                SKAction.run { [weak self] in
                    self?.completePromptContinuation(continuation)
                },
            ]),
            withKey: Self.promptWatchdogKey
        )

        let trackID = engine.currentSfx
        if !trackID.isEmpty {
            SoundEffectsController.shared.play(trackID: trackID)
        }
        let duration = SoundEffectsController.shared.cueDuration(of: trackID)
        run(
            SKAction.sequence([
                SKAction.wait(forDuration: duration),
                SKAction.run { [weak self] in
                    self?.completePromptContinuation(continuation)
                },
            ]),
            withKey: Self.promptSoundKey
        )
    }

    /// Replays the current word sound without gating the tray.
    func replayWordSound() {
        let trackID = engine.currentSfx
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
    }

    func completePromptContinuation(_ continuation: @escaping () -> Void) {
        guard promptContinuationArmed else { return }
        promptContinuationArmed = false
        removeAction(forKey: Self.promptWatchdogKey)
        removeAction(forKey: Self.promptSoundKey)
        continuation()
    }

    func showWordPrompt() {
        wordPromptNode?.removeFromParent()
        blankLetterNode = nil
        let geo = geometry
        let root = SKNode()
        root.name = Self.wordPromptNodeName
        root.position = geo.wordPromptCenter
        root.zPosition = Self.wordPromptZ

        let maxSide = max(geo.wordPromptMaxSide, 48)
        let fontSize = max(maxSide * 0.28, 18)
        let spelling = makeMaskedSpellingNode(fontSize: fontSize)
        spelling.zPosition = 2
        root.addChild(spelling)

        let hitHeight: CGFloat
        if let image = GateWordPlugImageSprites.image(named: engine.currentImageName) {
            let texture = SKTexture(image: image)
            SpriteSheetLoader.prepareTextureForScaledDisplay(texture)
            let sprite = SKSpriteNode(texture: texture)
            let texSize = texture.size()
            let maxDim = max(texSize.width, texSize.height)
            let scale = maxSide / max(maxDim, 1)
            sprite.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
            sprite.zPosition = 1
            root.addChild(sprite)

            let gap = fontSize * 0.35
            let totalHeight = sprite.size.height + gap + fontSize
            sprite.position = CGPoint(x: 0, y: (totalHeight - sprite.size.height) * 0.5)
            spelling.position = CGPoint(x: 0, y: -totalHeight * 0.5 + fontSize * 0.5)
            hitHeight = totalHeight * 1.15
        } else {
            // No illustration — masked spelling is the prompt.
            spelling.position = .zero
            hitHeight = max(fontSize * 1.4, maxSide * 0.5)
        }

        // Invisible hit pad so taps are reliable even on thin sprites.
        let hit = SKShapeNode(rectOf: CGSize(width: maxSide * 1.15, height: hitHeight))
        hit.fillColor = .clear
        hit.strokeColor = .clear
        hit.zPosition = 0
        hit.name = Self.wordPromptNodeName
        root.addChild(hit)

        addChild(root)
        wordPromptNode = root
    }

    /// Word letters plus a `_` blank for the missing sound, laid out under the illustration.
    func makeMaskedSpellingNode(fontSize: CGFloat) -> SKNode {
        let row = SKNode()
        row.name = Self.wordSpellingNodeName
        let word = engine.currentWord
        let blankLeads = engine.config.letterPosition == .starting
        let visible = word.isEmpty ? "" : String(blankLeads ? word.dropFirst() : word.dropLast())

        var lettersNode: SKNode?
        if !visible.isEmpty {
            let node = OutlinedLetterFactory.make(
                text: visible,
                fontSize: fontSize,
                disablesInteraction: true
            )
            node.name = "spellingLetters"
            row.addChild(node)
            lettersNode = node
        }
        let blank = OutlinedLetterFactory.make(
            text: "_",
            fontSize: fontSize,
            disablesInteraction: true
        )
        blank.name = Self.blankLetterNodeName
        row.addChild(blank)
        blankLetterNode = blank

        // Horizontal pack: measure after children exist, then center the row.
        let lettersWidth = lettersNode?.calculateAccumulatedFrame().width ?? 0
        let blankWidth = blank.calculateAccumulatedFrame().width
        let totalWidth = lettersWidth + blankWidth
        let leadWidth = blankLeads ? blankWidth : lettersWidth
        let leadX = -totalWidth * 0.5 + leadWidth * 0.5
        let trailX = totalWidth * 0.5 - (blankLeads ? lettersWidth : blankWidth) * 0.5
        blank.position = CGPoint(x: blankLeads ? leadX : trailX, y: 0)
        lettersNode?.position = CGPoint(x: blankLeads ? trailX : leadX, y: 0)
        return row
    }

    func setBlankLetterText(_ text: String) {
        guard let blankLetterNode else { return }
        for case let label as SKLabelNode in blankLetterNode.children {
            label.text = text
        }
    }

    func setBlankLetterFillColor(_ color: UIColor) {
        guard let blankLetterNode else { return }
        for case let label as SKLabelNode in blankLetterNode.children
        where label.zPosition == SceneLayer.LabelStack.fill {
            label.fontColor = color
        }
    }

    func flashBlankLetter(
        color: UIColor,
        clearColor: UIColor = .white,
        completion: (() -> Void)? = nil
    ) {
        guard let blankLetterNode else {
            completion?()
            return
        }
        let flash = SKAction.doubleFlash(
            count: 1,
            apply: { [weak self] in self?.setBlankLetterFillColor(color) },
            clear: { [weak self] in self?.setBlankLetterFillColor(clearColor) }
        )
        blankLetterNode.run(flash) {
            completion?()
        }
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

        if wordPromptNode(at: location) != nil {
            replayWordSound()
            return
        }

        guard let node = choiceNode(at: location) else { return }
        guard node.action(forKey: "springBack") == nil else { return }
        draggedNode = node
        dragStartPosition = node.position
        dragOffset = CGPoint(x: node.position.x - location.x, y: node.position.y - location.y)
        node.zPosition = Self.draggedZ
        startForceLiftSparkles(on: node)
        playForceLiftAnimation(toward: node.position)
        if let letter = node.userData?["letter"] as? String {
            playLetterPronunciation(letter)
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
        let letter = (node.userData?["letter"] as? String) ?? ""
        switch result {
        case let .correct(slotIndex, won):
            // Jump clip replaces the Force-lift pose once the tile snaps into the slot.
            handleCorrectDrop(node: node, id: id, slotIndex: slotIndex, won: won, letter: letter)
        case .incorrect:
            resumePlayerIdle()
            handleIncorrectDrop(node: node, letter: letter)
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

    func wordPromptNode(at point: CGPoint) -> SKNode? {
        let hits = nodes(at: point)
        for hit in hits {
            var current: SKNode? = hit
            while let node = current {
                if node.name == Self.wordPromptNodeName {
                    return wordPromptNode ?? node
                }
                current = node.parent
            }
        }
        return nil
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
