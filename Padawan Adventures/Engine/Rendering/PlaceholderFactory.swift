import SpriteKit
import UIKit

enum PlaceholderFactory {
    static func tileNode(for tile: Tile, at coord: GridCoord, config: IsometricConfig) -> SKNode {
        let container = SKNode()
        container.position = IsometricMath.gridToScreen(coord, config: config)
        container.zPosition = IsometricMath.depthSortValue(for: coord, config: config)

        switch tile.kind {
        case .floor(let isPit):
            let floor = horizontalFloorNode(isPit: isPit, config: config)
            container.addChild(floor)
            if isPit {
                addOverlay("O", to: container)
            }

        case .wall(let destructible, let hasDoor, let hasLadder):
            let wall = verticalWallNode(destructible: destructible, config: config)
            container.addChild(wall)
            if hasDoor {
                addOverlay("D", to: container, yOffset: config.wallHeight * 0.35)
            } else if hasLadder {
                addOverlay("L", to: container, yOffset: config.wallHeight * 0.35)
            }

        case .ramp:
            let floor = horizontalFloorNode(isPit: false, config: config, fillColor: UIColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1))
            container.addChild(floor)
            addOverlay("R", to: container)

        case .slide:
            let floor = horizontalFloorNode(isPit: false, config: config, fillColor: UIColor(red: 1.0, green: 0.85, blue: 0.85, alpha: 1))
            container.addChild(floor)
            addOverlay("S", to: container)
        }

        return container
    }

    /// Flat-top isometric floor tile with horizontal top and bottom edges.
    static func horizontalFloorNode(
        isPit: Bool,
        config: IsometricConfig,
        fillColor: UIColor? = nil
    ) -> SKShapeNode {
        let halfW = config.tileWidth / 2
        let depth = config.tileHeight

        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfW, y: 0))
        path.addLine(to: CGPoint(x: halfW, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -depth))
        path.addLine(to: CGPoint(x: -halfW, y: 0))
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.lineWidth = 2
        node.strokeColor = .black
        if let fillColor {
            node.fillColor = fillColor
        } else {
            node.fillColor = isPit ? UIColor(white: 0.75, alpha: 1) : .white
        }
        return node
    }

    /// Vertical wall face rising from the back (top) edge of the floor tile.
    static func verticalWallNode(destructible: Bool, config: IsometricConfig) -> SKShapeNode {
        let halfW = config.tileWidth / 2
        let wallHeight = config.wallHeight

        let path = CGMutablePath()
        path.move(to: CGPoint(x: -halfW, y: 0))
        path.addLine(to: CGPoint(x: halfW, y: 0))
        path.addLine(to: CGPoint(x: halfW, y: wallHeight))
        path.addLine(to: CGPoint(x: -halfW, y: wallHeight))
        path.closeSubpath()

        let node = SKShapeNode(path: path)
        node.lineWidth = 2
        node.strokeColor = .black
        node.fillColor = destructible ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.35, alpha: 1)
        return node
    }

    static func entityNode(for entity: GameEntity, config: IsometricConfig) -> SKNode {
        let container = SKNode()
        container.name = entity.isPlayer ? "player" : "entity-\(entity.id.uuidString)"

        let size = CGSize(width: config.tileWidth * 0.45, height: config.tileHeight * 1.2)
        let rect = SKShapeNode(rectOf: size, cornerRadius: 4)
        rect.fillColor = entity.isPlayer ? UIColor(red: 0.2, green: 0.5, blue: 0.95, alpha: 1) : UIColor(white: 0.85, alpha: 1)
        rect.strokeColor = .black
        rect.lineWidth = 2
        rect.zPosition = 1

        let label = SKLabelNode(text: String(entity.letter))
        label.fontSize = 18
        label.fontName = "Menlo-Bold"
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
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
        anchor: GridCoord,
        viewCenter: CGPoint,
        config: IsometricConfig
    ) {
        node.position = IsometricMath.viewPosition(
            for: entity.position,
            anchor: anchor,
            viewCenter: viewCenter,
            config: config
        )
        node.zPosition = IsometricMath.depthSortValue(for: entity.position, config: config) + 0.5
    }

    private static func addOverlay(_ text: String, to container: SKNode, yOffset: CGFloat = 0) {
        let label = SKLabelNode(text: text)
        label.fontSize = 14
        label.fontName = "Menlo-Bold"
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: yOffset)
        label.zPosition = 2
        container.addChild(label)
    }
}
