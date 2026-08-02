import SpriteKit
import UIKit

extension PitScene {
    func makeLetterNode(token: PitMinigameEngine.LetterToken, side: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "letter:\(token.id.uuidString)"
        root.userData = ["id": token.id.uuidString, "letter": token.letter]
        root.zPosition = SceneLayer.letterPlatform

        var tileHeight: CGFloat = side * 0.6
        if let tile = makeFloorTileNode(
            library: floorTileSetLibrary,
            config: isoConfig,
            using: &placementRNG
        ) {
            let measured = tile.calculateAccumulatedFrame()
            if measured.width > 1 {
                tile.setScale(side / measured.width)
            }
            // Center the isometric floor diamond on the letter root so the glyph and
            // Kam land on the tile face (anchor alone sits at the north tip).
            let bounds = tile.calculateAccumulatedFrame()
            tileHeight = bounds.height
            // Nudge the tile up one full height; letter moves down by the same amount.
            tile.position = CGPoint(x: -bounds.midX, y: -bounds.midY + tileHeight)
            tile.zPosition = 0
            root.addChild(tile)

            if let sprite = tile.children.first as? SKSpriteNode {
                if engine.isSpent(token.id) {
                    applyPlatformTint(sprite, color: platformCorrectTint, blend: 0.45)
                }
                platformNodes[token.id] = sprite
            }
        } else {
            let fallback = SKShapeNode(rectOf: CGSize(width: side, height: tileHeight), cornerRadius: 4)
            fallback.fillColor = UIColor(white: 0.22, alpha: 1)
            fallback.strokeColor = UIColor(white: 0.65, alpha: 1)
            fallback.lineWidth = 2
            fallback.position = CGPoint(x: 0, y: tileHeight)
            fallback.zPosition = 0
            if engine.isSpent(token.id) {
                fallback.fillColor = platformCorrectTint
            }
            root.addChild(fallback)
        }

        let engraved = makeEngravedLetter(text: token.letter, fontSize: letterFontSize)
        engraved.position = CGPoint(x: 0, y: -tileHeight)
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
