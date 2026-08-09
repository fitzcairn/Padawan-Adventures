import SpriteKit
import UIKit

extension GateSoundOutWordScene {
    // MARK: - Capacitors

    /// Capacitor sprite plus a face overlay: blank choices show `speaker.wave.2.bubble`
    /// (swapping to `.fill` while their sound plays); placed capacitors show the grapheme.
    /// Correct drops crossfade the play icon → letter via `revealGrapheme(on:_:)`.
    func makeCapacitorNode(name: String, diameter: CGFloat, grapheme: String?) -> SKNode {
        let root = SKNode()
        root.name = name
        root.zPosition = 20

        var faceOffsetY: CGFloat = 0
        var spriteHeight = diameter
        if let texture = GateSpellingCapacitorSprites.load(),
           let capacitor = GateSpellingCapacitorSprites.sprite(texture: texture, side: diameter) {
            capacitor.zPosition = 0
            root.addChild(capacitor)
            spriteHeight = capacitor.size.height
            // Top-face center, then 7% of sprite height top padding (shift glyph down).
            faceOffsetY = GateSpellingCapacitorSprites.letterOffsetY(for: spriteHeight)
                - spriteHeight * 0.07
        } else {
            let circle = SKShapeNode(circleOfRadius: diameter * 0.5)
            circle.fillColor = circleFill
            circle.strokeColor = UIColor(white: 0.65, alpha: 1)
            circle.lineWidth = 2
            circle.zPosition = 0
            circle.name = "capacitorFallback"
            root.addChild(circle)
            faceOffsetY = -spriteHeight * 0.07
        }

        let facePosition = CGPoint(x: 0, y: faceOffsetY)
        if let grapheme {
            let label = OutlinedLetterFactory.make(
                text: grapheme,
                fontSize: capacitorGlyphFontSize(for: diameter),
                style: .capacitorFace,
                disablesInteraction: true
            )
            label.name = Self.capacitorGlyphName
            label.position = facePosition
            label.zPosition = 1
            root.addChild(label)
        } else {
            let play = MinigamePlaySoundIcon.makeNode(side: capacitorPlayIconSide(for: diameter))
            play.position = CGPoint(
                x: facePosition.x + MinigamePlaySoundIcon.opticalXOffset(containerWidth: diameter),
                y: facePosition.y
            )
            play.zPosition = 1
            root.addChild(play)
        }

        return root
    }

    static let capacitorGlyphName = "capacitorGlyph"

    func capacitorGlyphFontSize(for diameter: CGFloat) -> CGFloat {
        diameter * 0.5 * 1.35 * 0.85 * 0.95 * 0.95
    }

    func capacitorPlayIconSide(for diameter: CGFloat) -> CGFloat {
        capacitorGlyphFontSize(for: diameter) * 0.85 * 0.6
    }

    /// Crossfades the play cue into the grapheme that capacitor was hiding.
    func revealGrapheme(on root: SKNode, _ grapheme: String) {
        let play = MinigamePlaySoundIcon.find(in: root)
        if let play { MinigamePlaySoundIcon.cancelPulse(play) }
        let existingGlyph = root.childNode(withName: Self.capacitorGlyphName)
        // Face center is local (0, y); play icons may be optically nudged on x.
        let faceY = play?.position.y ?? existingGlyph?.position.y ?? 0

        let stack = OutlinedLetterFactory.make(
            text: grapheme,
            fontSize: capacitorGlyphFontSize(for: laidOutDiameter),
            style: .capacitorFace,
            disablesInteraction: true
        )
        stack.name = Self.capacitorGlyphName
        stack.position = CGPoint(x: 0, y: faceY)
        stack.zPosition = 1
        stack.alpha = 0
        existingGlyph?.removeFromParent()
        root.addChild(stack)

        let duration = Self.letterRevealDuration
        if let play {
            play.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: duration),
                SKAction.removeFromParent(),
            ]))
        }
        stack.run(SKAction.fadeIn(withDuration: duration))
    }

    func makeEndpointNode(radius: CGFloat, name: String) -> SKNode {
        let root = SKNode()
        root.name = name
        root.zPosition = 8
        root.isUserInteractionEnabled = false

        if let texture = GateSpellingCapacitorSprites.load(),
           let capacitor = GateSpellingCapacitorSprites.sprite(texture: texture, side: radius * 2) {
            capacitor.zPosition = 0
            root.addChild(capacitor)
            return root
        }

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = circleFill
        circle.strokeColor = UIColor(white: 0.65, alpha: 1)
        circle.lineWidth = 2
        circle.name = "capacitorFallback"
        root.addChild(circle)
        return root
    }

    // MARK: - Prompt row

    func makePromptLetterNode(_ letter: String, fontSize: CGFloat, index: Int) -> SKNode {
        let node = OutlinedLetterFactory.make(
            text: letter,
            fontSize: fontSize,
            style: .proportional,
            disablesInteraction: true
        )
        // Center alignment boxes each glyph on its own bounds; baseline keeps the word level.
        for case let label as SKLabelNode in node.children {
            label.verticalAlignmentMode = .baseline
        }
        node.name = "promptLetter:\(index)"
        node.zPosition = 30
        return node
    }

    func setPromptColor(at index: Int, color: UIColor) {
        guard promptLetterNodes.indices.contains(index),
              let fill = OutlinedLetterFactory.fillLabel(in: promptLetterNodes[index]) else {
            return
        }
        fill.fontColor = color
    }

    /// Pending and solved graphemes read white; only the active one is orange.
    func updatePromptColors() {
        for index in promptLetterNodes.indices {
            setPromptColor(at: index, color: promptPendingColor)
        }
    }

    // MARK: - Tints

    func capacitorSprite(in root: SKNode) -> SKSpriteNode? {
        root.childNode(withName: "capacitor") as? SKSpriteNode
    }

    func capacitorFallback(in root: SKNode) -> SKShapeNode? {
        root.childNode(withName: "capacitorFallback") as? SKShapeNode
    }

    func applyCapacitorTint(to root: SKNode, color: UIColor, blend: CGFloat) {
        if let sprite = capacitorSprite(in: root) {
            sprite.color = color
            sprite.colorBlendFactor = blend
            return
        }
        capacitorFallback(in: root)?.fillColor = color
    }

    func clearCapacitorTint(on root: SKNode) {
        if let sprite = capacitorSprite(in: root) {
            sprite.colorBlendFactor = 0
            return
        }
        capacitorFallback(in: root)?.fillColor = circleFill
    }

    // MARK: - Hit testing

    func choice(at point: CGPoint) -> UUID? {
        for (id, node) in choiceNodes where node.calculateAccumulatedFrame().contains(point) {
            return id
        }
        return nil
    }

    /// True when `point` hits the word band of the prompt plate.
    func isPromptWordTap(_ point: CGPoint) -> Bool {
        prompt?.region(at: point) == .word
    }

    func isPictureTap(_ point: CGPoint) -> Bool {
        prompt?.region(at: point) == .picture
    }
}
