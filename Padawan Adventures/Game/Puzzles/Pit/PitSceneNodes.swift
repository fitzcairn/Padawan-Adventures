import SpriteKit
import UIKit

extension PitScene {
    func makeLetterNode(token: PitMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        var spriteHeight = side
        if let texture = pitSpriteSetLibrary.randomTexture(using: &placementRNG),
           let sprite = PitSpriteFactory.sprite(texture: texture, side: side) {
            sprite.zPosition = 0
            sprite.alpha = 0.90 // spritesheet platform only — letters stay fully opaque
            if engine.isSpent(token.id) {
                applyPlatformTint(sprite, color: platformCorrectTint, blend: 0.45)
            }
            root.addChild(sprite)
            platformNodes[token.id] = sprite
            spriteHeight = sprite.size.height
        } else {
            let fallback = SKShapeNode(circleOfRadius: side * 0.5)
            fallback.fillColor = UIColor(white: 0.22, alpha: 1)
            fallback.strokeColor = UIColor(white: 0.65, alpha: 1)
            fallback.lineWidth = 2
            fallback.zPosition = 0
            fallback.alpha = 0.90
            if engine.isSpent(token.id) {
                fallback.fillColor = platformCorrectTint
            }
            root.addChild(fallback)
        }

        let engraved = makeEngravedLetter(text: token.letter, fontSize: letterFontSize)
        // Bottom padding = 10% of sprite height → shift letter up toward the platform top.
        engraved.position = CGPoint(x: 0, y: spriteHeight * 0.10)
        engraved.zPosition = 1
        engraved.alpha = 1
        engraved.isUserInteractionEnabled = false
        root.addChild(engraved)

        return root
    }

    /// Letter with white outline + inner shadow so it reads as carved into the platform.
    func makeEngravedLetter(text: String, fontSize: CGFloat) -> SKNode {
        let root = SKNode()
        let offset = max(1.0, fontSize * 0.045)

        // 1px white outline (8-neighbor copies behind the engraved stack).
        for dx in -1...1 {
            for dy in -1...1 {
                guard dx != 0 || dy != 0 else { continue }
                let outline = SKLabelNode(text: text)
                outline.fontName = AppFont.name
                outline.fontSize = fontSize
                outline.fontColor = .white
                outline.verticalAlignmentMode = .center
                outline.horizontalAlignmentMode = .center
                outline.position = CGPoint(x: CGFloat(dx), y: CGFloat(dy))
                outline.zPosition = 0
                root.addChild(outline)
            }
        }

        let highlight = SKLabelNode(text: text)
        highlight.fontName = AppFont.name
        highlight.fontSize = fontSize
        highlight.fontColor = UIColor.white.withAlphaComponent(0.30)
        highlight.verticalAlignmentMode = .center
        highlight.horizontalAlignmentMode = .center
        highlight.position = CGPoint(x: offset, y: -offset)
        highlight.zPosition = 1
        root.addChild(highlight)

        let shadow = SKLabelNode(text: text)
        shadow.fontName = AppFont.name
        shadow.fontSize = fontSize
        shadow.fontColor = UIColor.black.withAlphaComponent(0.55)
        shadow.verticalAlignmentMode = .center
        shadow.horizontalAlignmentMode = .center
        shadow.position = CGPoint(x: -offset, y: offset)
        shadow.zPosition = 2
        root.addChild(shadow)

        let label = SKLabelNode(text: text)
        label.fontName = AppFont.name
        label.fontSize = fontSize
        label.fontColor = UIColor(white: 0.10, alpha: 1)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 3
        label.alpha = 1
        root.addChild(label)

        return root
    }

    func applyPlatformTint(_ sprite: SKSpriteNode, color: UIColor, blend: CGFloat) {
        sprite.color = color
        sprite.colorBlendFactor = blend
    }

    func clearPlatformTint(_ sprite: SKSpriteNode) {
        sprite.color = .white
        sprite.colorBlendFactor = 0
    }
}
