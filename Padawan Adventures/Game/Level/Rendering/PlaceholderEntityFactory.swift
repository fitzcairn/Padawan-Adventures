import SpriteKit
import UIKit

extension PlaceholderFactory {
    @MainActor
    static func entityNode(
        for entity: GameEntity,
        config: IsometricConfig,
        fillColor: UIColor? = nil,
        spriteLibrary: SpriteLibrary? = nil,
        spriteConfig: SpriteConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        enemySprite: (id: String, config: SpriteConfig)? = nil,
        treasureItemID: String? = nil
    ) -> SKNode {
        if let kind = entity.pickupKind {
            return pickupNode(
                kind: kind,
                entityID: entity.id,
                config: config,
                spriteLibrary: spriteLibrary,
                itemsConfig: itemsConfig,
                treasureItemID: treasureItemID
            )
        }

        if entity.isPlayer,
           let library = spriteLibrary,
           let spriteConfig,
           library.animation(named: CompassDirection.down.animationName(locomotion: .idle)) != nil {
            return playerSpriteNode(config: config, library: library, spriteConfig: spriteConfig)
        }

        if entity.isEnemy,
           let library = spriteLibrary,
           let enemySprite,
           library.animation(
               id: enemySprite.id,
               named: CompassDirection.down.animationName(locomotion: .idle)
           ) != nil {
            return enemySpriteNode(
                entityID: entity.id,
                config: config,
                library: library,
                spriteConfig: enemySprite.config,
                libraryID: enemySprite.id
            )
        }

        let container = SKNode()
        container.name = entity.isPlayer ? "player" : "entity-\(entity.id.uuidString)"

        // Tall billboard so the sprite reads clearly above the floor diamond.
        let size = CGSize(width: config.tileWidth * 0.55, height: config.tileHeight * 2.2)
        let rect = SKShapeNode(rectOf: size, cornerRadius: 6)
        rect.fillColor = fillColor
            ?? (entity.isPlayer ? playerFillColor : defaultEntityFillColor)
        rect.strokeColor = .white
        rect.lineWidth = 3
        rect.zPosition = entityBodyZ
        // Feet near the tile center; body extends upward toward the camera's "up".
        rect.position = CGPoint(x: 0, y: size.height * 0.35)

        let label = SKLabelNode(text: String(entity.letter))
        label.fontSize = 22
        label.fontName = AppFont.name
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = rect.position
        label.zPosition = entityLabelZ

        container.addChild(rect)
        container.addChild(label)
        return container
    }

    /// Player container hosting an `AnimatedSpriteNode` (name `"player"`).
    @MainActor
    static func playerSpriteNode(
        config: IsometricConfig,
        library: SpriteLibrary,
        spriteConfig: SpriteConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "player"
        container.userData = NSMutableDictionary(dictionary: ["usesSpriteAnimation": true])

        let height = spriteDisplayHeight(isoConfig: config, spriteConfig: spriteConfig)
        let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
        sprite.fitHeight(height)
        sprite.zPosition = entityBodyZ
        // Shift toward bottom of screen by anchor_correction % of scaled height.
        let correction = height * CGFloat(spriteConfig.anchorCorrection) / 100
        sprite.position = CGPoint(x: 0, y: -correction)
        container.addChild(sprite)

        let idleName = CompassDirection.down.animationName(locomotion: .idle)
        sprite.play(name: idleName, library: library)
        return container
    }

    /// Enemy container hosting an `AnimatedSpriteNode`, keyed to `libraryID` in the sprite library.
    @MainActor
    static func enemySpriteNode(
        entityID: UUID,
        config: IsometricConfig,
        library: SpriteLibrary,
        spriteConfig: SpriteConfig,
        libraryID: String
    ) -> SKNode {
        let container = SKNode()
        container.name = "entity-\(entityID.uuidString)"
        container.userData = NSMutableDictionary(dictionary: ["usesSpriteAnimation": true])

        let height = spriteDisplayHeight(isoConfig: config, spriteConfig: spriteConfig)
        let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
        sprite.fitHeight(height)
        sprite.zPosition = entityBodyZ
        // Shift toward bottom of screen by anchor_correction % of scaled height.
        let correction = height * CGFloat(spriteConfig.anchorCorrection) / 100
        sprite.position = CGPoint(x: 0, y: -correction)
        container.addChild(sprite)

        sprite.play(
            name: CompassDirection.down.animationName(locomotion: .idle),
            library: library,
            libraryID: libraryID
        )
        return container
    }

    static func usesSpriteAnimation(_ node: SKNode) -> Bool {
        (node.userData?["usesSpriteAnimation"] as? Bool) == true
    }

    /// Applied on top of per-sprite YAML `scale` so world entities render larger.
    static let spriteDisplayScaleMultiplier: CGFloat = 1.2

    /// Display height = `wall_height` × `scale` × `spriteDisplayScaleMultiplier`.
    /// Width follows texture aspect at play time.
    static func spriteDisplayHeight(
        isoConfig: IsometricConfig,
        spriteConfig: SpriteConfig
    ) -> CGFloat {
        isoConfig.wallHeight * CGFloat(spriteConfig.scale) * spriteDisplayScaleMultiplier
    }

    /// Provisional square size from wall height (width refined when the texture is known).
    static func spriteDisplaySize(
        isoConfig: IsometricConfig,
        spriteConfig: SpriteConfig
    ) -> CGSize {
        let height = spriteDisplayHeight(isoConfig: isoConfig, spriteConfig: spriteConfig)
        return CGSize(width: height, height: height)
    }

    @MainActor
    static func pickupNode(
        kind: PickupKind,
        entityID: UUID,
        config: IsometricConfig,
        spriteLibrary: SpriteLibrary? = nil,
        itemsConfig: ItemsConfig? = nil,
        treasureItemID: String? = nil
    ) -> SKNode {
        let container = SKNode()
        container.name = "pickup-\(entityID.uuidString)"

        // Treasure art is per-level; health/energy keep their PickupKind id.
        let itemID = (kind == .treasure ? treasureItemID : nil) ?? kind.rawValue

        let spriteConfig = itemsConfig?.spriteConfig(id: itemID)

        if let library = spriteLibrary,
           let spriteConfig,
           library.animation(id: itemID, named: "idle") != nil {
            // Display height = wall_height × items.yaml `sprite.scale` × 1.2.
            let height = spriteDisplayHeight(isoConfig: config, spriteConfig: spriteConfig)
            let correction = height * CGFloat(spriteConfig.anchorCorrection) / 100
            if let highlight = itemsConfig?.highlight(id: itemID) {
                let glow = SparkleEmitterFactory.makeNode(
                    config: highlight,
                    referenceHeight: height
                )
                glow.position = CGPoint(
                    x: 0,
                    y: height * CGFloat(highlight.yOffset) - correction
                )
                container.addChild(glow)
            }
            let sprite = AnimatedSpriteNode(size: CGSize(width: height, height: height))
            sprite.zPosition = entityBodyZ
            // Feet (bottom-middle) on the tile center; optional anchor_correction nudge.
            sprite.position = CGPoint(x: 0, y: -correction)
            container.addChild(sprite)
            // Lock height before play so the first texture assign cannot stick at
            // native frame pixels; re-fit after play in case animate resets size.
            sprite.fitHeight(height)
            sprite.play(name: "idle", library: library, libraryID: itemID)
            sprite.fitHeight(height)
            return container
        }

        // SF Symbol fallback still honors items.yaml scale when present.
        let iconSide = pickupIconSize * CGFloat(spriteConfig?.scale ?? 1)
        let iconY = config.tileHeight * 0.35
        if let highlight = itemsConfig?.highlight(id: itemID) {
            let glow = SparkleEmitterFactory.makeNode(
                config: highlight,
                referenceHeight: iconSide
            )
            glow.position = CGPoint(x: 0, y: iconY)
            container.addChild(glow)
        }

        let sprite = SKSpriteNode(texture: pickupTexture(kind: kind, side: iconSide))
        sprite.size = CGSize(width: iconSide, height: iconSide)
        // Lift slightly above the tile center so the icon sits on the floor diamond.
        sprite.position = CGPoint(x: 0, y: iconY)
        sprite.zPosition = entityBodyZ
        container.addChild(sprite)

        startIdleBounce(on: sprite)
        return container
    }

    static func pickupTexture(kind: PickupKind, side: CGFloat = pickupIconSize) -> SKTexture {
        let systemName: String
        let tint: UIColor
        switch kind {
        case .health:
            systemName = "heart.fill"
            tint = healthPickupColor
        case .energy:
            systemName = "bolt.fill"
            tint = energyPickupColor
        case .treasure:
            systemName = "shippingbox.fill"
            tint = treasurePickupColor
        }

        // Bake the tint into a bitmap — SKTexture ignores UIImage dynamic tints and
        // otherwise draws SF Symbols as black template images.
        let pointSize = max(side, 1)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config) else {
            return SKTexture()
        }
        let size = CGSize(width: pointSize, height: pointSize)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            symbol
                .withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }
}
