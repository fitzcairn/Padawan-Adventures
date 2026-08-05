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
        let wordRow = makeWordRow(fontSize: fontSize)
        wordRow.zPosition = 2
        root.addChild(wordRow)

        let hitHeight: CGFloat
        if let image = GateWordPlugImageSprites.image(named: engine.targetEntry.image) {
            let texture = SKTexture(image: image)
            SpriteSheetLoader.prepareTextureForScaledDisplay(texture)
            let sprite = SKSpriteNode(texture: texture)
            let texSize = texture.size()
            let maxDim = max(texSize.width, texSize.height)
            let scale = maxSide / max(maxDim, 1)
            sprite.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
            sprite.name = Self.pictureNodeName
            sprite.zPosition = 1
            sprite.isUserInteractionEnabled = false
            root.addChild(sprite)

            let gap = fontSize * 0.35
            let rowHeight = wordRow.calculateAccumulatedFrame().height
            let totalHeight = sprite.size.height + gap + max(rowHeight, fontSize)
            sprite.position = CGPoint(x: 0, y: (totalHeight - sprite.size.height) * 0.5)
            wordRow.position = CGPoint(x: 0, y: -totalHeight * 0.5 + fontSize * 0.35)
            hitHeight = totalHeight * 1.15

            let pictureHit = SKShapeNode(
                rectOf: CGSize(width: maxSide * 1.15, height: sprite.size.height * 1.1)
            )
            pictureHit.fillColor = .clear
            pictureHit.strokeColor = .clear
            pictureHit.zPosition = 0
            pictureHit.name = Self.pictureNodeName
            pictureHit.position = sprite.position
            root.addChild(pictureHit)
        } else {
            wordRow.position = .zero
            hitHeight = max(fontSize * 1.4, maxSide * 0.5)
        }

        let hit = SKShapeNode(rectOf: CGSize(width: maxSide * 1.15, height: hitHeight))
        hit.fillColor = .clear
        hit.strokeColor = .clear
        hit.zPosition = -1
        hit.name = Self.pictureNodeName
        root.addChild(hit)

        addChild(root)
        promptNode = root
    }

    func makeWordRow(fontSize: CGFloat) -> SKNode {
        let container = SKNode()
        container.name = Self.wordTextNodeName

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

        let frame = container.calculateAccumulatedFrame()
        let hit = SKShapeNode(
            rectOf: CGSize(
                width: max(frame.width * 1.15, fontSize),
                height: max(frame.height * 1.3, fontSize)
            )
        )
        hit.fillColor = .clear
        hit.strokeColor = .clear
        hit.zPosition = -1
        hit.name = Self.wordTextNodeName
        container.addChild(hit)

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
