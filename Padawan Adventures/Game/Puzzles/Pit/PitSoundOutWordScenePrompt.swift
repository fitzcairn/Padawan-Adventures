import SpriteKit
import UIKit

extension PitSoundOutWordScene {
    // MARK: - Prompt audio

    /// Plays the target word track, then continues (with a watchdog).
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

        let trackID = engine.wordTrackID
        if !trackID.isEmpty {
            SoundEffectsController.shared.play(trackID: trackID)
            if let promptNode,
               let picture = promptNode.childNode(withName: Self.pictureNodeName) {
                MinigameCRTPromptPlate.pulseIcons(in: picture, forTrackID: trackID)
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

    /// Replays the word sound without gating step progression.
    func replayWordSound() {
        let trackID = engine.wordTrackID
        guard !trackID.isEmpty else { return }
        SoundEffectsController.shared.play(trackID: trackID)
        if let promptNode,
           let picture = promptNode.childNode(withName: Self.pictureNodeName) {
            MinigameCRTPromptPlate.pulseIcons(in: picture, forTrackID: trackID)
        }
    }

    func completePromptContinuation(_ continuation: @escaping () -> Void) {
        guard promptContinuationArmed else { return }
        promptContinuationArmed = false
        removeAction(forKey: Self.promptWatchdogKey)
        removeAction(forKey: Self.promptSoundKey)
        continuation()
    }

    // MARK: - Prompt UI

    func showPrompt() {
        promptNode?.removeFromParent()
        wordGraphemeNodes = []
        let geo = geometry
        let root = SKNode()
        root.position = geo.promptCenter
        root.zPosition = Self.promptZ

        let maxSide = max(geo.promptMaxSide, 48)
        let fontSize = max(maxSide * 0.28, 18)
        let font = AppFont.uiKit(size: fontSize)

        let wordRow = makeWordRow(fontSize: fontSize)
        let wordContentWidth = max(
            wordRow.calculateAccumulatedFrame().width + fontSize * 0.5,
            fontSize
        )
        let wordPlateSize = StarWarsConsoleChrome.plateSize(
            forContent: CGSize(width: wordContentWidth, height: font.lineHeight)
        )
        let wordPlate = MinigameCRTPromptPlate.makeWordPlate(
            size: wordPlateSize,
            name: Self.wordTextNodeName
        )
        wordPlate.zPosition = 1

        if let image = GateWordPlugImageSprites.image(named: engine.targetEntry.image) {
            let picture = MinigameCRTPromptPlate.makePicturePlate(
                image: image,
                contentSide: maxSide,
                name: Self.pictureNodeName
            )
            picture.zPosition = 1
            // Fill the block the geometry reserved, so the fan clamp stays accurate.
            let gap = max(
                geo.promptBlockHeight - picture.size.height - wordPlateSize.height,
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
        // Baseline-aligned letters, centred on the plate's screen.
        wordRow.position = CGPoint(x: 0, y: -font.capHeight * 0.5)
        wordRow.zPosition = 2
        wordPlate.addChild(wordRow)

        addChild(root)
        promptNode = root
    }

    func makeWordRow(fontSize: CGFloat) -> SKNode {
        let container = SKNode()

        let graphemes = engine.targetGraphemes
        guard !graphemes.isEmpty else { return container }

        var nodes: [SKNode] = []
        var widths: [CGFloat] = []
        let gap = fontSize * 0.12
        for (index, grapheme) in graphemes.enumerated() {
            let node = OutlinedLetterFactory.make(
                text: grapheme,
                fontSize: fontSize,
                disablesInteraction: true
            )
            // Center alignment boxes each glyph on its own bounds; baseline keeps the word level.
            for case let label as SKLabelNode in node.children {
                label.verticalAlignmentMode = .baseline
            }
            node.name = "promptLetter:\(index)"
            let width = max(node.calculateAccumulatedFrame().width, fontSize * 0.4)
            nodes.append(node)
            widths.append(width)
        }

        let totalWidth = widths.reduce(0, +) + gap * CGFloat(max(nodes.count - 1, 0))
        var cursorX = -totalWidth * 0.5
        for (index, node) in nodes.enumerated() {
            node.position = CGPoint(x: cursorX + widths[index] * 0.5, y: 0)
            container.addChild(node)
            cursorX += widths[index] + gap
        }
        wordGraphemeNodes = nodes

        return container
    }

    func setGraphemeFillColor(at index: Int, _ color: UIColor) {
        guard wordGraphemeNodes.indices.contains(index) else { return }
        OutlinedLetterFactory.fillLabel(in: wordGraphemeNodes[index])?.fontColor = color
    }

    /// `doubleFlash` ends on `clear`. Activating uses white/orange; accepting uses green/white.
    func flashGrapheme(
        at index: Int,
        apply: UIColor,
        clear: UIColor,
        count: Int,
        completion: (() -> Void)? = nil
    ) {
        guard wordGraphemeNodes.indices.contains(index) else {
            completion?()
            return
        }
        let node = wordGraphemeNodes[index]
        let flash = SKAction.doubleFlash(
            count: count,
            apply: { [weak self] in self?.setGraphemeFillColor(at: index, apply) },
            clear: { [weak self] in self?.setGraphemeFillColor(at: index, clear) }
        )
        node.run(flash) {
            completion?()
        }
    }
}
