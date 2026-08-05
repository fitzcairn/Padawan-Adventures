import SpriteKit
import UIKit

extension GateSoundOutWordScene {
    // MARK: - Capacitors

    /// Capacitor sprite plus an optional grapheme on its top face. Blank choices pass
    /// `grapheme: nil` and reveal the glyph later via `revealGrapheme(on:_:)`.
    func makeCapacitorNode(name: String, diameter: CGFloat, grapheme: String?) -> SKNode {
        let root = SKNode()
        root.name = name
        root.zPosition = 20

        var labelOffsetY: CGFloat = 0
        var spriteHeight = diameter
        if let texture = GateSpellingCapacitorSprites.load(),
           let capacitor = GateSpellingCapacitorSprites.sprite(texture: texture, side: diameter) {
            capacitor.zPosition = 0
            root.addChild(capacitor)
            spriteHeight = capacitor.size.height
            // Top-face center, then 7% of sprite height top padding (shift glyph down).
            labelOffsetY = GateSpellingCapacitorSprites.letterOffsetY(for: spriteHeight)
                - spriteHeight * 0.07
        } else {
            let circle = SKShapeNode(circleOfRadius: diameter * 0.5)
            circle.fillColor = circleFill
            circle.strokeColor = UIColor(white: 0.65, alpha: 1)
            circle.lineWidth = 2
            circle.zPosition = 0
            circle.name = "capacitorFallback"
            root.addChild(circle)
            labelOffsetY = -spriteHeight * 0.07
        }

        let label = OutlinedLetterFactory.make(
            text: grapheme ?? "",
            fontSize: capacitorGlyphFontSize(for: diameter),
            style: .capacitorFace,
            disablesInteraction: true
        )
        label.name = Self.capacitorGlyphName
        label.position = CGPoint(x: 0, y: labelOffsetY)
        label.zPosition = 1
        label.alpha = grapheme == nil ? 0 : 1
        root.addChild(label)

        return root
    }

    static let capacitorGlyphName = "capacitorGlyph"

    func capacitorGlyphFontSize(for diameter: CGFloat) -> CGFloat {
        diameter * 0.5 * 1.35 * 0.85 * 0.95 * 0.95
    }

    /// Swaps the blank face for the real grapheme and fades it in.
    func revealGrapheme(on root: SKNode, _ grapheme: String) {
        guard let blank = root.childNode(withName: Self.capacitorGlyphName) else { return }
        let stack = OutlinedLetterFactory.make(
            text: grapheme,
            fontSize: capacitorGlyphFontSize(for: laidOutDiameter),
            style: .capacitorFace,
            disablesInteraction: true
        )
        stack.name = Self.capacitorGlyphName
        stack.position = blank.position
        stack.zPosition = blank.zPosition
        stack.alpha = 0
        blank.removeFromParent()
        root.addChild(stack)
        stack.run(SKAction.fadeIn(withDuration: Self.letterRevealDuration))
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
        node.name = "promptLetter:\(index)"
        node.zPosition = 30
        return node
    }

    /// Word illustration for the chosen word; `nil` when the catalog entry has no image.
    func makePictureNode(side: CGFloat) -> SKSpriteNode? {
        guard side > 0,
              let image = GateWordPlugImageSprites.image(named: engine.targetEntry.image) else {
            return nil
        }
        let texture = SKTexture(image: image)
        let textureSize = texture.size()
        let maxDimension = max(textureSize.width, textureSize.height)
        guard maxDimension > 0 else { return nil }
        let scale = side / maxDimension
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(
            width: textureSize.width * scale,
            height: textureSize.height * scale
        )
        node.name = "wordPicture"
        node.zPosition = 30
        node.isUserInteractionEnabled = false
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

    func promptLetterIndex(at point: CGPoint) -> Int? {
        for (index, node) in promptLetterNodes.enumerated() {
            // Thin glyphs need a forgiving target for small fingers.
            let frame = node.calculateAccumulatedFrame().insetBy(
                dx: -promptFontSize * 0.15,
                dy: -promptFontSize * 0.15
            )
            if frame.contains(point) { return index }
        }
        return nil
    }

    func isPictureTap(_ point: CGPoint) -> Bool {
        guard let pictureNode else { return false }
        return pictureNode.calculateAccumulatedFrame().contains(point)
    }
}
