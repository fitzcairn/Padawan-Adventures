import SpriteKit
import UIKit

enum PlaceholderFactory {
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
            let floor = horizontalFloorNode(isPit: isPit, config: config)
            container.addChild(floor)
            if isPit {
                addOverlay("O", to: container, yOffset: -config.tileHeight * 0.35)
            }

        case .wall(let destructible, let hasDoor, let hasLadder):
            container.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
            let faces: WallFaceSet
            if let world {
                faces = IsometricTileGeometry.visibleFaces(at: coord, in: world)
            } else {
                faces = .all
            }
            let wall = perspectiveWallNode(
                destructible: destructible,
                faces: faces,
                config: config
            )
            container.addChild(wall)
            if hasDoor {
                addOverlay("D", to: container, yOffset: config.wallHeight * 0.35 - config.tileHeight * 0.5)
            } else if hasLadder {
                addOverlay("L", to: container, yOffset: config.wallHeight * 0.35 - config.tileHeight * 0.5)
            }

        case .ramp:
            container.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
            let floor = horizontalFloorNode(
                isPit: false,
                config: config,
                fillColor: UIColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1)
            )
            container.addChild(floor)
            addOverlay("R", to: container, yOffset: -config.tileHeight * 0.35)

        case .slide:
            container.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
            let floor = horizontalFloorNode(
                isPit: false,
                config: config,
                fillColor: UIColor(red: 1.0, green: 0.85, blue: 0.85, alpha: 1)
            )
            container.addChild(floor)
            addOverlay("S", to: container, yOffset: -config.tileHeight * 0.35)
        }

        return container
    }

    /// Flat-top isometric floor diamond (horizontal tile).
    static func horizontalFloorNode(
        isPit: Bool,
        config: IsometricConfig,
        fillColor: UIColor? = nil
    ) -> SKShapeNode {
        let node = SKShapeNode(path: IsometricTileGeometry.floorPath(config: config))
        node.lineWidth = 2
        node.strokeColor = .black
        if let fillColor {
            node.fillColor = fillColor
        } else {
            node.fillColor = isPit ? UIColor(white: 0.75, alpha: 1) : .white
        }
        return node
    }

    /// Perspective wall block: left/right slanted faces + optional top, based on tile sides.
    static func perspectiveWallNode(
        destructible: Bool,
        faces: WallFaceSet = .all,
        config: IsometricConfig
    ) -> SKNode {
        let container = SKNode()
        container.name = "wall-block"

        let baseLeft = destructible ? UIColor(white: 0.62, alpha: 1) : UIColor(white: 0.42, alpha: 1)
        let baseRight = destructible ? UIColor(white: 0.48, alpha: 1) : UIColor(white: 0.28, alpha: 1)
        let baseTop = destructible ? UIColor(white: 0.7, alpha: 1) : UIColor(white: 0.5, alpha: 1)

        if faces.contains(.left) {
            let left = SKShapeNode(path: IsometricTileGeometry.leftWallFacePath(config: config))
            left.name = "wall-face-left"
            left.lineWidth = 2
            left.strokeColor = .black
            left.fillColor = baseLeft
            left.zPosition = 0
            container.addChild(left)
        }

        if faces.contains(.right) {
            let right = SKShapeNode(path: IsometricTileGeometry.rightWallFacePath(config: config))
            right.name = "wall-face-right"
            right.lineWidth = 2
            right.strokeColor = .black
            right.fillColor = baseRight
            right.zPosition = 1
            container.addChild(right)
        }

        if faces.contains(.top) {
            let top = SKShapeNode(path: IsometricTileGeometry.topWallFacePath(config: config))
            top.name = "wall-face-top"
            top.lineWidth = 2
            top.strokeColor = .black
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

    static func entityNode(for entity: GameEntity, config: IsometricConfig) -> SKNode {
        let container = SKNode()
        container.name = entity.isPlayer ? "player" : "entity-\(entity.id.uuidString)"

        // Tall billboard so the sprite reads clearly above the floor diamond.
        let size = CGSize(width: config.tileWidth * 0.55, height: config.tileHeight * 2.2)
        let rect = SKShapeNode(rectOf: size, cornerRadius: 6)
        rect.fillColor = entity.isPlayer
            ? UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1)
            : UIColor(white: 0.9, alpha: 1)
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

    private static func addOverlay(_ text: String, to container: SKNode, yOffset: CGFloat = 0) {
        let label = SKLabelNode(text: text)
        label.fontSize = 14
        label.fontName = "Menlo-Bold"
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: yOffset)
        label.zPosition = 3
        container.addChild(label)
    }
}
