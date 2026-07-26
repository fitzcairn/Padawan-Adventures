import SpriteKit
import UIKit

enum PlaceholderFactory {
    // Explicit sRGB so SKShapeNode fillColor round-trips equal (UIColor.white is gray-space).
    static let floorColor = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    /// Dark brown pit fill so hazards read clearly against white floors.
    static let pitColor = UIColor(red: 0.28, green: 0.14, blue: 0.06, alpha: 1)
    /// Brighter gray so 1-tile partitions stay readable at fit-scale overview.
    static let wallColor = UIColor(white: 0.72, alpha: 1)
    /// Light yellow soft walls the player can destroy.
    static let destructibleWallColor = UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 1)
    /// Light green multi-tile gate barriers.
    static let gateColor = UIColor(red: 0.55, green: 0.9, blue: 0.55, alpha: 1)
    /// Raised roof fill between wall tops.
    static let ceilingColor = UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    /// Screen-space Y drop for pit tiles so voids read below the surrounding floor.
    static let pitDropPixels: CGFloat = 5

    /// World position for a floor cell, including the pit drop when `isPit`.
    static func floorScreenPosition(
        for tile: Tile,
        at coord: GridCoord,
        config: IsometricConfig
    ) -> CGPoint {
        let screen = IsometricMath.gridToScreen(coord, config: config)
        guard tile.isPit else { return screen }
        return CGPoint(x: screen.x, y: screen.y - pitDropPixels)
    }

    /// Nested z biases must stay well below one depth step and the entity/wall
    /// half-step (`entitySortValue` = depth + 0.5). With `ignoresSiblingOrder`,
    /// SpriteKit sorts by accumulated z — integer face offsets (+1/+2) used to
    /// let sprites draw over front wall sides while wall tops still won.
    static let wallFaceLeftZ: CGFloat = 0.01
    static let wallFaceRightZ: CGFloat = 0.02
    static let wallFaceTopZ: CGFloat = 0.03
    static let entityBodyZ: CGFloat = 0.01
    static let entityLabelZ: CGFloat = 0.02

    static func tileNode(
        for tile: Tile,
        at coord: GridCoord,
        in world: GameWorld? = nil,
        config: IsometricConfig,
        floorTileSetLibrary: FloorTileSetLibrary? = nil
    ) -> SKNode {
        let container = SKNode()

        switch tile.kind {
        case .floor(let isPit):
            // Drop pits a few pixels so the void reads below neighbouring floor.
            container.position = floorScreenPosition(for: tile, at: coord, config: config)
            container.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
            if let library = floorTileSetLibrary,
               let tileSet = library.tileSet,
               let tileID = tile.floorTileID,
               let texture = library.texture(tileID),
               let frame = library.frame(tileID) {
                let sprite = floorTileNode(
                    tileID: tileID,
                    texture: texture,
                    frame: frame,
                    diamond: tileSet.meta.diamond,
                    config: config
                )
                sprite.zPosition = 0.02
                container.addChild(sprite)
            } else {
                // Fallback diamond only when baked floor art is missing.
                let underlay = horizontalFloorNode(
                    config: config,
                    fillColor: isPit ? pitColor : floorColor
                )
                underlay.strokeColor = .clear
                container.addChild(underlay)
            }

        case .wall(let destructible):
            container.position = IsometricMath.gridToScreen(coord, config: config)
            container.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
            let color = destructible ? destructibleWallColor : wallColor
            // Interior solid walls (not bordering walkable space) stay unrendered → black.
            // Destructible walls always render so soft targets stay visible.
            if destructible {
                let faces = world.map { IsometricTileGeometry.visibleFaces(at: coord, in: $0) } ?? .all
                container.addChild(perspectiveWallNode(color: color, faces: faces, config: config))
            } else if let world, IsometricTileGeometry.shouldRenderWall(at: coord, in: world) {
                let faces = IsometricTileGeometry.visibleFaces(at: coord, in: world)
                container.addChild(perspectiveWallNode(color: color, faces: faces, config: config))
            } else if world == nil {
                container.addChild(perspectiveWallNode(color: color, faces: .all, config: config))
            }

        case .gate:
            container.position = IsometricMath.gridToScreen(coord, config: config)
            container.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
            let faces = world.map { IsometricTileGeometry.visibleFaces(at: coord, in: $0) } ?? .all
            container.addChild(perspectiveWallNode(color: gateColor, faces: faces, config: config))
        }

        return container
    }

    /// Raised gray diamond at wall-top height (CEILING overlay).
    static func ceilingNode(config: IsometricConfig) -> SKShapeNode {
        let node = SKShapeNode(path: IsometricTileGeometry.topWallFacePath(config: config))
        node.name = "ceiling"
        node.lineWidth = 1
        node.fillColor = ceilingColor
        node.strokeColor = UIColor(white: 0.2, alpha: 1)
        return node
    }

    /// Flat-top isometric floor diamond (horizontal tile).
    static func horizontalFloorNode(
        isPit: Bool = false,
        config: IsometricConfig,
        fillColor: UIColor? = nil
    ) -> SKShapeNode {
        let node = SKShapeNode(path: IsometricTileGeometry.floorPath(config: config))
        node.lineWidth = 1
        if let fillColor {
            node.fillColor = fillColor
            node.strokeColor = UIColor(white: 0.2, alpha: 1)
        } else if isPit {
            node.fillColor = pitColor
            node.strokeColor = UIColor(white: 0.1, alpha: 1)
        } else {
            node.fillColor = floorColor
            node.strokeColor = UIColor(white: 0.2, alpha: 1)
        }
        return node
    }

    /// Floor tile sprite placed so the art's north corner coincides with the container origin.
    static func floorTileNode(
        tileID: String,
        texture: SKTexture,
        frame: FloorTileSet.Frame,
        diamond: FloorTileSet.Diamond,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "floor-sprite"
        container.userData = NSMutableDictionary(dictionary: ["floorTileID": tileID])

        let sx = config.tileWidth / max(diamond.w, 1)
        let sy = config.tileHeight / max(diamond.h, 1)
        let sprite = SKSpriteNode(texture: texture)
        sprite.anchorPoint = CGPoint(
            x: frame.anchor.x / max(CGFloat(frame.w), 1),
            y: 1 - frame.anchor.y / max(CGFloat(frame.h), 1)
        )
        sprite.size = CGSize(
            width: CGFloat(frame.w) * sx,
            height: CGFloat(frame.h) * sy
        )
        sprite.position = .zero
        sprite.zPosition = 0
        container.addChild(sprite)
        return container
    }

    /// Identity key for reusing base floor nodes across renderer rebuilds.
    static func floorIdentity(for tile: Tile) -> String? {
        guard case .floor(let isPit) = tile.kind else { return nil }
        let id = tile.floorTileID ?? ""
        return "\(id)|\(isPit ? 1 : 0)"
    }

    /// Identity key for reusing wall / gate block nodes (nil when nothing should draw).
    static func wallIdentity(for tile: Tile, at coord: GridCoord, in world: GameWorld) -> String? {
        switch tile.kind {
        case .wall(let destructible):
            // Interior solid walls stay unrendered; destructibles always draw.
            if !destructible && !IsometricTileGeometry.shouldRenderWall(at: coord, in: world) {
                return nil
            }
            let faces = IsometricTileGeometry.visibleFaces(at: coord, in: world)
            return "wall|\(destructible ? 1 : 0)|\(faces.rawValue)"
        case .gate:
            let faces = IsometricTileGeometry.visibleFaces(at: coord, in: world)
            return "gate|\(faces.rawValue)"
        case .floor:
            return nil
        }
    }

    /// Identity key for reusing ceiling diamonds (nil when the cell needs no ceiling).
    static func ceilingIdentity(at coord: GridCoord, in world: GameWorld) -> String? {
        guard IsometricTileGeometry.needsCeiling(at: coord, in: world) else { return nil }
        return "ceiling"
    }

    /// Perspective wall block: left/right slanted faces + optional top, based on tile sides.
    static func perspectiveWallNode(
        color: UIColor? = nil,
        faces: WallFaceSet = .all,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "wall-block"

        let base = color ?? wallColor
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let baseLeft = UIColor(hue: hue, saturation: saturation, brightness: min(1, brightness * 1.05), alpha: alpha)
        let baseRight = UIColor(hue: hue, saturation: saturation, brightness: max(0, brightness * 0.75), alpha: alpha)
        let baseTop = UIColor(hue: hue, saturation: saturation, brightness: min(1, brightness * 1.2), alpha: alpha)

        let stroke = UIColor(white: 0.05, alpha: 1)
        let lineWidth: CGFloat = 2.5

        if faces.contains(.left) {
            let left = SKShapeNode(path: IsometricTileGeometry.leftWallFacePath(config: config))
            left.name = "wall-face-left"
            left.lineWidth = lineWidth
            left.strokeColor = stroke
            left.fillColor = baseLeft
            left.zPosition = wallFaceLeftZ
            container.addChild(left)
        }

        if faces.contains(.right) {
            let right = SKShapeNode(path: IsometricTileGeometry.rightWallFacePath(config: config))
            right.name = "wall-face-right"
            right.lineWidth = lineWidth
            right.strokeColor = stroke
            right.fillColor = baseRight
            right.zPosition = wallFaceRightZ
            container.addChild(right)
        }

        if faces.contains(.top) {
            let top = SKShapeNode(path: IsometricTileGeometry.topWallFacePath(config: config))
            top.name = "wall-face-top"
            top.lineWidth = lineWidth
            top.strokeColor = stroke
            top.fillColor = baseTop
            top.zPosition = wallFaceTopZ
            container.addChild(top)
        }

        return container
    }

    static let playerFillColor = UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1)
    static let defaultEntityFillColor = UIColor(white: 0.9, alpha: 1)

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
        label.fontName = "Menlo-Bold"
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
        sprite.targetHeight = height
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
        sprite.targetHeight = height
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

    /// Display height = `wall_height` × `scale`. Width follows texture aspect at play time.
    static func spriteDisplayHeight(
        isoConfig: IsometricConfig,
        spriteConfig: SpriteConfig
    ) -> CGFloat {
        isoConfig.wallHeight * CGFloat(spriteConfig.scale)
    }

    /// Provisional square size from wall height (width refined when the texture is known).
    static func spriteDisplaySize(
        isoConfig: IsometricConfig,
        spriteConfig: SpriteConfig
    ) -> CGSize {
        let height = spriteDisplayHeight(isoConfig: isoConfig, spriteConfig: spriteConfig)
        return CGSize(width: height, height: height)
    }

    static let pickupIconSize: CGFloat = 30
    static let pickupBounceAmplitude: CGFloat = 5
    static let healthPickupColor = UIColor.systemRed
    static let energyPickupColor = UIColor.systemYellow
    static let treasurePickupColor = UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1)

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

        if let library = spriteLibrary,
           let spriteConfig = itemsConfig?.spriteConfig(id: itemID),
           library.animation(id: itemID, named: "idle") != nil {
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
            sprite.targetHeight = height
            sprite.zPosition = entityBodyZ
            // Feet (bottom-middle) on the tile center; optional anchor_correction nudge.
            sprite.position = CGPoint(x: 0, y: -correction)
            container.addChild(sprite)
            sprite.play(name: "idle", library: library, libraryID: itemID)
            return container
        }

        let iconY = config.tileHeight * 0.35
        if let highlight = itemsConfig?.highlight(id: itemID) {
            let glow = SparkleEmitterFactory.makeNode(
                config: highlight,
                referenceHeight: pickupIconSize
            )
            glow.position = CGPoint(x: 0, y: iconY)
            container.addChild(glow)
        }

        let sprite = SKSpriteNode(texture: pickupTexture(kind: kind))
        sprite.size = CGSize(width: pickupIconSize, height: pickupIconSize)
        // Lift slightly above the tile center so the icon sits on the floor diamond.
        sprite.position = CGPoint(x: 0, y: iconY)
        sprite.zPosition = entityBodyZ
        container.addChild(sprite)

        startIdleBounce(on: sprite)
        return container
    }

    static func pickupTexture(kind: PickupKind) -> SKTexture {
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
        let config = UIImage.SymbolConfiguration(pointSize: pickupIconSize, weight: .bold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config) else {
            return SKTexture()
        }
        let size = CGSize(width: pickupIconSize, height: pickupIconSize)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            symbol
                .withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        return SKTexture(image: image)
    }

    static func startIdleBounce(on node: SKNode) {
        node.removeAction(forKey: "pickupBounce")
        let up = SKAction.moveBy(x: 0, y: pickupBounceAmplitude, duration: 0.45)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -pickupBounceAmplitude, duration: 0.45)
        down.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, down])), withKey: "pickupBounce")
    }

    /// One bounce then fade; calls `completion` when finished.
    static func playCollectAnimation(on node: SKNode, completion: @escaping () -> Void) {
        SparkleEmitterFactory.stop(in: node)
        let icon = node.children.first { !($0 is SKEmitterNode) } ?? node
        icon.removeAction(forKey: "pickupBounce")
        let up = SKAction.moveBy(x: 0, y: pickupBounceAmplitude, duration: 0.2)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -pickupBounceAmplitude, duration: 0.2)
        down.timingMode = .easeInEaseOut
        let fade = SKAction.fadeOut(withDuration: 0.25)
        node.run(.sequence([
            .run { icon.run(.sequence([up, down])) },
            .wait(forDuration: 0.4),
            fade,
            .run(completion),
        ]))
    }

    static func applyAnimationFrame(_ frame: Int, to node: SKNode) {
        let scales: [CGFloat] = [1.0, 1.06, 1.0, 0.94]
        node.setScale(scales[frame % scales.count])
    }

    static func updateEntityNode(
        _ node: SKNode,
        entity: GameEntity,
        config: IsometricConfig
    ) {
        node.position = IsometricMath.entityScreenPosition(entity.position, config: config)
        node.zPosition = IsometricMath.entitySortValue(for: entity.position, config: config)
    }

}
