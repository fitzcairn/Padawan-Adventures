import SpriteKit
import UIKit

extension GateScene {
    func makeLetterNode(token: GateMinigameEngine.LetterToken, radius: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = 10

        var labelOffsetY: CGFloat = 0
        var spriteHeight: CGFloat = radius * 2
        if let texture = GateSpellingCapacitorSprites.load(),
           let capacitor = GateSpellingCapacitorSprites.sprite(texture: texture, side: radius * 2) {
            capacitor.zPosition = 0
            root.addChild(capacitor)
            spriteHeight = capacitor.size.height
            // Top-face center, then 7% of sprite height top padding (shift letter down).
            labelOffsetY = GateSpellingCapacitorSprites.letterOffsetY(for: spriteHeight)
                - spriteHeight * 0.07
        } else {
            let circle = SKShapeNode(circleOfRadius: radius)
            circle.fillColor = circleFill
            circle.strokeColor = UIColor(white: 0.65, alpha: 1)
            circle.lineWidth = 2
            circle.zPosition = 0
            circle.name = "capacitorFallback"
            root.addChild(circle)
            labelOffsetY = -spriteHeight * 0.07
        }

        let fontSize = radius * 1.35 * 0.85 * 0.95 * 0.95
        let letter = OutlinedLetterFactory.make(
            text: token.letter,
            fontSize: fontSize,
            style: .capacitorFace,
            disablesInteraction: true
        )
        letter.position = CGPoint(x: 0, y: labelOffsetY)
        letter.zPosition = 1
        root.addChild(letter)

        return root
    }

    func makeEndpointNode(radius: CGFloat, name: String) -> SKNode {
        if let texture = GateSpellingCapacitorSprites.load(),
           let capacitor = GateSpellingCapacitorSprites.sprite(texture: texture, side: radius * 2) {
            let root = SKNode()
            root.name = name
            root.zPosition = 8
            root.isUserInteractionEnabled = false
            capacitor.zPosition = 0
            root.addChild(capacitor)
            return root
        }

        let circle = SKShapeNode(circleOfRadius: radius)
        circle.fillColor = circleFill
        circle.strokeColor = UIColor(white: 0.65, alpha: 1)
        circle.lineWidth = 2
        circle.zPosition = 8
        circle.name = name
        circle.isUserInteractionEnabled = false
        return circle
    }
    func capacitorSprite(in root: SKNode) -> SKSpriteNode? {
        root.childNode(withName: "capacitor") as? SKSpriteNode
    }

    func capacitorFallback(in root: SKNode) -> SKShapeNode? {
        (root.childNode(withName: "capacitorFallback") as? SKShapeNode)
            ?? root.children.compactMap { $0 as? SKShapeNode }.first
            ?? (root as? SKShapeNode)
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
}
