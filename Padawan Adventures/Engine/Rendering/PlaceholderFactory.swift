import SpriteKit
import UIKit

enum PlaceholderFactory {
    // Explicit sRGB so SKShapeNode fillColor round-trips equal (UIColor.white is gray-space).
    static let floorColor = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    /// Brighter gray so 1-tile partitions stay readable at fit-scale overview.
    static let wallColor = UIColor(white: 0.72, alpha: 1)

    static func tileNode(
        for tile: Tile,
        at coord: GridCoord,
        in world: GameWorld? = nil,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.position = IsometricMath.gridToScreen(coord, config: config)

        switch tile.kind {
        case .floor(let isPit):
            container.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
            // Pits are transparent — no floor rendered (black void shows through).
            if !isPit {
                container.addChild(horizontalFloorNode(config: config, fillColor: floorColor))
            }

        case .wall(_, let hasDoor):
            if hasDoor {
                // Doorways show as floor so the passage reads as walkable ground.
                container.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                container.addChild(horizontalFloorNode(config: config, fillColor: floorColor))
            } else {
                container.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                // Interior solid walls (not bordering walkable space) stay unrendered → black.
                if shouldRenderWall(at: coord, in: world) {
                    let faces: WallFaceSet
                    if let world {
                        faces = IsometricTileGeometry.visibleFaces(at: coord, in: world)
                    } else {
                        faces = .all
                    }
                    let wall = perspectiveWallNode(
                        color: wallColor,
                        faces: faces,
                        config: config
                    )
                    container.addChild(wall)
                }
            }
        }

        return container
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
            // Pits are transparent when rendered via this helper.
            node.fillColor = .clear
            node.strokeColor = .clear
        } else {
            node.fillColor = floorColor
            node.strokeColor = UIColor(white: 0.2, alpha: 1)
        }
        return node
    }

    /// Perspective wall block: left/right slanted faces + optional top, based on tile sides.
    static func perspectiveWallNode(
        destructible: Bool = false,
        color: UIColor? = nil,
        faces: WallFaceSet = .all,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "wall-block"
        _ = destructible

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
            left.zPosition = 0
            container.addChild(left)
        }

        if faces.contains(.right) {
            let right = SKShapeNode(path: IsometricTileGeometry.rightWallFacePath(config: config))
            right.name = "wall-face-right"
            right.lineWidth = lineWidth
            right.strokeColor = stroke
            right.fillColor = baseRight
            right.zPosition = 1
            container.addChild(right)
        }

        if faces.contains(.top) {
            let top = SKShapeNode(path: IsometricTileGeometry.topWallFacePath(config: config))
            top.name = "wall-face-top"
            top.lineWidth = lineWidth
            top.strokeColor = stroke
            top.fillColor = baseTop
            top.zPosition = 2
            container.addChild(top)
        }

        return container
    }

    /// Backward-compatible helper used by older tests; full perspective wall with all faces.
    static func verticalWallNode(destructible: Bool, config: IsometricConfig) -> SKNode {
        perspectiveWallNode(destructible: destructible, faces: .all, config: config)
    }

    static let playerFillColor = UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1)
    static let defaultEntityFillColor = UIColor(white: 0.9, alpha: 1)

    static func entityNode(
        for entity: GameEntity,
        config: IsometricConfig,
        fillColor: UIColor? = nil
    ) -> SKNode {
        if let kind = entity.pickupKind {
            return pickupNode(kind: kind, entityID: entity.id, config: config)
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
        rect.zPosition = 1
        // Feet near the tile center; body extends upward toward the camera's "up".
        rect.position = CGPoint(x: 0, y: size.height * 0.35)

        let label = SKLabelNode(text: String(entity.letter))
        label.fontSize = 22
        label.fontName = "Menlo-Bold"
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = rect.position
        label.zPosition = 2

        container.addChild(rect)
        container.addChild(label)
        return container
    }

    static let pickupIconSize: CGFloat = 30
    static let pickupBounceAmplitude: CGFloat = 5
    static let healthPickupColor = UIColor.systemRed
    static let energyPickupColor = UIColor.systemYellow
    static let treasurePickupColor = UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1)

    static func pickupNode(
        kind: PickupKind,
        entityID: UUID,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "pickup-\(entityID.uuidString)"

        let sprite = SKSpriteNode(texture: pickupTexture(kind: kind))
        sprite.size = CGSize(width: pickupIconSize, height: pickupIconSize)
        // Lift slightly above the tile center so the icon sits on the floor diamond.
        sprite.position = CGPoint(x: 0, y: config.tileHeight * 0.35)
        sprite.zPosition = 1
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
        let icon = node.children.first ?? node
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

    /// Walls that don't border walkable space stay black (unrendered over the scene background).
    private static func shouldRenderWall(at coord: GridCoord, in world: GameWorld?) -> Bool {
        guard let world else { return true }
        for (dx, dy) in GridCoord.cardinals {
            let neighbor = coord.neighbor(dx: dx, dy: dy)
            guard world.isInBounds(neighbor), let tile = world.tile(at: neighbor) else { continue }
            if isWalkableSurface(tile) { return true }
        }
        return false
    }

    private static func isWalkableSurface(_ tile: Tile) -> Bool {
        switch tile.kind {
        case .floor(let isPit):
            return !isPit
        case .wall(_, let hasDoor):
            return hasDoor
        }
    }
}
