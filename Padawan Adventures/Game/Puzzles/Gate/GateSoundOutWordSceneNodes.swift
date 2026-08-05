import SpriteKit
import UIKit

extension GateSoundOutWordScene {
    // MARK: - Capacitors

    /// Capacitor sprite plus a face overlay: blank choices show `play` (swapping to
    /// `play.fill` while their sound plays); placed capacitors show the grapheme.
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
        } else if let play = makePlayIconNode(side: capacitorPlayIconSide(for: diameter)) {
            // play / play.fill are optically left-heavy; nudge so they read centered.
            play.position = CGPoint(x: facePosition.x + diameter * 0.03, y: facePosition.y)
            play.zPosition = 1
            root.addChild(play)
        }

        return root
    }

    static let capacitorGlyphName = "capacitorGlyph"
    static let capacitorPlayIconName = "capacitorPlayIcon"
    static let capacitorPlayIconActionKey = "capacitorPlayIconPulse"

    func capacitorGlyphFontSize(for diameter: CGFloat) -> CGFloat {
        diameter * 0.5 * 1.35 * 0.85 * 0.95 * 0.95
    }

    func capacitorPlayIconSide(for diameter: CGFloat) -> CGFloat {
        capacitorGlyphFontSize(for: diameter) * 0.85
    }

    /// White SF Symbol baked into a texture (SKTexture ignores UIImage tints).
    func bakePlayIconTexture(systemName: String, side: CGFloat) -> SKTexture? {
        let pointSize = max(side, 1)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config) else {
            return nil
        }
        let size = CGSize(width: pointSize, height: pointSize)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            symbol
                .withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    /// Idle + filled play textures for `side`, reused across the choice set.
    func playIconTexturePair(side: CGFloat) -> (idle: SKTexture, filled: SKTexture)? {
        if let cached = playIconTextures, abs(cached.side - side) < 0.5 {
            return (cached.idle, cached.filled)
        }
        guard let idle = bakePlayIconTexture(systemName: "play", side: side),
              let filled = bakePlayIconTexture(systemName: "play.fill", side: side) else {
            return nil
        }
        playIconTextures = (side, idle, filled)
        return (idle, filled)
    }

    /// Idle `play` icon; swapped to `play.fill` for the duration of a letter-sound tap.
    func makePlayIconNode(side: CGFloat) -> SKSpriteNode? {
        guard let textures = playIconTexturePair(side: side) else { return nil }
        let node = SKSpriteNode(
            texture: textures.idle,
            size: CGSize(width: side, height: side)
        )
        node.name = Self.capacitorPlayIconName
        node.isUserInteractionEnabled = false
        return node
    }

    /// Shows `play.fill` while `trackID` plays, then restores the idle `play` outline.
    func pulsePlayIcon(on root: SKNode, forTrackID trackID: String) {
        guard let icon = root.childNode(withName: Self.capacitorPlayIconName) as? SKSpriteNode
        else { return }
        let side = max(icon.size.width, icon.size.height)
        guard let textures = playIconTexturePair(side: side) else { return }
        icon.removeAction(forKey: Self.capacitorPlayIconActionKey)
        icon.texture = textures.filled
        icon.run(
            SKAction.sequence([
                SKAction.wait(
                    forDuration: SoundEffectsController.shared.cueDuration(of: trackID)
                ),
                SKAction.run { [weak icon] in icon?.texture = textures.idle },
            ]),
            withKey: Self.capacitorPlayIconActionKey
        )
    }

    /// Crossfades the play cue into the grapheme that capacitor was hiding.
    func revealGrapheme(on root: SKNode, _ grapheme: String) {
        let play = root.childNode(withName: Self.capacitorPlayIconName)
        play?.removeAction(forKey: Self.capacitorPlayIconActionKey)
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
