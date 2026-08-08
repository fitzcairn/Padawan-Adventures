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
            if let wordPromptNode {
                MinigameCRTPromptPlate.pulseIcons(in: wordPromptNode, forTrackID: trackID)
            }
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
        if let wordPromptNode {
            MinigameCRTPromptPlate.pulseIcons(in: wordPromptNode, forTrackID: trackID)
        }
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
        let font = AppFont.uiKit(size: fontSize)
        let spelling = makeMaskedSpellingNode(fontSize: fontSize)
        let wordContentWidth = max(
            spelling.calculateAccumulatedFrame().width + fontSize * 0.5,
            fontSize
        )
        let wordPlateSize = StarWarsConsoleChrome.plateSize(
            forContent: CGSize(width: wordContentWidth, height: font.lineHeight)
        )
        let wordPlate = MinigameCRTPromptPlate.makeWordPlate(
            size: wordPlateSize,
            name: Self.wordPromptNodeName
        )
        wordPlate.zPosition = 1

        if let image = GateWordPlugImageSprites.image(named: engine.currentImageName) {
            let picture = MinigameCRTPromptPlate.makePicturePlate(
                image: image,
                contentSide: maxSide,
                name: Self.wordPromptNodeName
            )
            picture.zPosition = 1
            let gap = max(
                geo.wordPromptBlockHeight - picture.size.height - wordPlateSize.height,
                fontSize * 0.1
            )
            let total = picture.size.height + gap + wordPlateSize.height
            picture.position = CGPoint(x: 0, y: (total - picture.size.height) * 0.5)
            wordPlate.position = CGPoint(x: 0, y: -total * 0.5 + wordPlateSize.height * 0.5)
            root.addChild(picture)
        } else {
            wordPlate.position = .zero
        }

        root.addChild(wordPlate)
        spelling.position = CGPoint(x: 0, y: -font.capHeight * 0.5)
        spelling.zPosition = 2
        wordPlate.addChild(spelling)

        addChild(root)
        wordPromptNode = root
    }

    /// Word letters plus a rectangle blank for the missing sound, laid out under the illustration.
    /// Each grapheme is its own baseline-aligned stack so the blank doesn't float above the rest.
    /// When `filledLetter` is set, the blank run is replaced by that letter with natural string spacing (no blank gap).
    func makeMaskedSpellingNode(fontSize: CGFloat, filledLetter: String? = nil) -> SKNode {
        let row = SKNode()
        row.name = Self.wordSpellingNodeName
        let units = spellingDisplayUnits(filledLetter: filledLetter)
        guard !units.isEmpty else { return row }

        let blankLeads = engine.config.letterPosition == .starting
        let showingBlank = filledLetter == nil
        let widths = units.map { spellingLetterWidth($0, fontSize: fontSize) }
        // Extra gap only while the empty box is visible — drop it once a letter fills the blank.
        let blankLetterGap = showingBlank
            ? OutlinedLetterFactory.blankSize(fontSize: fontSize).width * 0.05
            : 0
        var gapsBefore = [CGFloat](repeating: 0, count: units.count)
        if showingBlank {
            for index in units.indices {
                if blankLeads {
                    if units[index] != "_",
                       index > 0,
                       units[index - 1] == "_",
                       units[..<index].allSatisfy({ $0 == "_" }) {
                        gapsBefore[index] = blankLetterGap
                    }
                } else if units[index] == "_",
                          index > 0,
                          units[index - 1] != "_",
                          units[index...].allSatisfy({ $0 == "_" }) {
                    gapsBefore[index] = blankLetterGap
                }
            }
        }
        let totalWidth = zip(widths, gapsBefore).map(+).reduce(0, +)
        var cursorX = -totalWidth * 0.5
        blankLetterNode = nil

        for (index, unit) in units.enumerated() {
            let node: SKNode
            if unit == "_" {
                node = OutlinedLetterFactory.makeBlank(
                    fontSize: fontSize,
                    disablesInteraction: true
                )
            } else {
                node = OutlinedLetterFactory.make(
                    text: unit,
                    fontSize: fontSize,
                    disablesInteraction: true
                )
                applySpellingBaselineAlignment(to: node)
            }
            let isAnswerSlot = blankLeads ? index == 0 : index == units.count - 1
            if isAnswerSlot {
                node.name = Self.blankLetterNodeName
                blankLetterNode = node
            } else {
                node.name = "spellingLetter:\(index)"
            }
            cursorX += gapsBefore[index]
            node.position = CGPoint(x: cursorX + widths[index] * 0.5, y: 0)
            row.addChild(node)
            cursorX += widths[index]
        }
        return row
    }

    /// Masked characters while empty; when filled, blank run collapses to the letter so spacing matches a normal word.
    func spellingDisplayUnits(filledLetter: String?) -> [String] {
        let masked = engine.maskedPromptText
        guard !masked.isEmpty else { return [] }
        let blankLeads = engine.config.letterPosition == .starting
        guard let filled = filledLetter, filled != "_", !filled.isEmpty else {
            return masked.map(String.init)
        }
        if blankLeads {
            let rest = String(masked.drop(while: { $0 == "_" }))
            return [filled] + rest.map(String.init)
        }
        let rest = String(masked.reversed().drop(while: { $0 == "_" }).reversed())
        return rest.map(String.init) + [filled]
    }

    /// Match GateSoundOutWord prompt packing so every grapheme shares one baseline.
    func applySpellingBaselineAlignment(to root: SKNode) {
        for case let label as SKLabelNode in root.children {
            label.verticalAlignmentMode = .baseline
        }
    }

    func spellingLetterWidth(_ letter: String, fontSize: CGFloat) -> CGFloat {
        if letter == "_" {
            return OutlinedLetterFactory.blankSize(fontSize: fontSize).width
        }
        let font = AppFont.uiKit(size: max(1, fontSize))
        return ceil((letter as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Shows a real letter in the interactive blank, or restores the rectangle when `text` is `"_"`.
    /// Relays out the spelling row so a filled letter uses normal string spacing (no blank gap).
    func setBlankLetterText(_ text: String) {
        guard let row = blankLetterNode?.parent
            ?? wordPromptNode?.childNode(withName: "//\(Self.wordSpellingNodeName)"),
              let parent = row.parent
        else { return }

        let fontSize = blankLetterNode.flatMap { OutlinedLetterFactory.fontSize(from: $0) }
            ?? row.children.compactMap { OutlinedLetterFactory.fontSize(from: $0) }.first
            ?? 18
        let position = row.position
        let zPosition = row.zPosition
        row.removeFromParent()

        let filled: String? = (text == "_") ? nil : text
        let newRow = makeMaskedSpellingNode(fontSize: fontSize, filledLetter: filled)
        newRow.position = position
        newRow.zPosition = zPosition
        parent.addChild(newRow)
    }

    func setBlankLetterFillColor(_ color: UIColor) {
        guard let blankLetterNode else { return }
        if let stroke = OutlinedLetterFactory.blankFill(in: blankLetterNode) {
            stroke.strokeColor = color
            return
        }
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
        guard node.action(forKey: "springBack") == nil,
              node.action(forKey: Self.snapIntoSlotActionKey) == nil else { return }
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

        let slotIndex = engine.roundIndex
        guard geometry.isDrop(node.position, onSlot: slotIndex) else {
            node.zPosition = Self.trayTilesZ
            resumePlayerIdle()
            springBack(node, to: dragStartPosition)
            return
        }

        isUserInteractionEnabled = false
        let target = geometry.slotCenter(slotIndex)
        snapIntoSlot(node, to: target) { [weak self] in
            guard let self else { return }
            self.resolveDrop(node: node, id: id)
        }
    }

    /// Resolves a drop that has already been accepted by geometry (and snapped into the slot).
    func resolveDrop(node: SKNode, id: UUID) {
        guard let result = engine.accept(choiceID: id) else {
            node.zPosition = Self.trayTilesZ
            resumePlayerIdle()
            isUserInteractionEnabled = true
            springBack(node, to: dragStartPosition)
            return
        }

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
