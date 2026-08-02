import SpriteKit
import UIKit

extension PitScene {
    func makeLetterNode(token: PitMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = SceneLayer.letterPlatform

        // Letter root == Kam feet on land (`AnimatedSpriteNode` keeps feet on node position).
        // Center the floor tile on that point so the tile middle matches the sprite bottom.
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

            if let sprite = tile.children.first as? SKSpriteNode {
                if engine.isSpent(token.id) {
                    applyPlatformTint(sprite, color: platformCorrectTint, blend: 0.45)
                }
                platformNodes[token.id] = sprite
            }
        } else {
            let fallback = SKShapeNode(rectOf: CGSize(width: side, height: side * 0.6), cornerRadius: 4)
            fallback.fillColor = UIColor(white: 0.22, alpha: 1)
            fallback.strokeColor = UIColor(white: 0.65, alpha: 1)
            fallback.lineWidth = 2
            fallback.position = .zero
            fallback.zPosition = 0
            if engine.isSpent(token.id) {
                fallback.fillColor = platformCorrectTint
            }
            root.addChild(fallback)
        }

        let letter = OutlinedLetterFactory.make(
            text: token.letter,
            fontSize: letterFontSize,
            disablesInteraction: true
        )
        letter.position = .zero
        letter.zPosition = 1
        root.addChild(letter)

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
