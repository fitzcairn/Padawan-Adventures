import SpriteKit

final class IsometricRenderer {
    private let config: IsometricConfig
    private let worldRoot = SKNode()
    private let worldLayer = SKNode()
    private let entityLayer = SKNode()
    private let playerLayer = SKNode()
    private var entityNodes: [UUID: SKNode] = [:]
    private var playerNode: SKNode?
    private var viewCenter: CGPoint = .zero

    init(config: IsometricConfig = IsometricConfig()) {
        self.config = config
    }

    func attach(to scene: SKScene) {
        worldRoot.removeAllChildren()
        entityLayer.removeAllChildren()
        playerLayer.removeAllChildren()
        worldLayer.removeAllChildren()
        entityNodes.removeAll()
        playerNode = nil

        viewCenter = CGPoint(
            x: scene.size.width * (0.5 - scene.anchorPoint.x),
            y: scene.size.height * (0.5 - scene.anchorPoint.y)
        )

        worldRoot.addChild(worldLayer)
        worldRoot.addChild(entityLayer)
        scene.addChild(worldRoot)
        scene.addChild(playerLayer)
    }

    func render(world: GameWorld, anchor: GridCoord) {
        worldLayer.removeAllChildren()

        for story in 0..<world.storyCount {
            for y in 0..<world.height {
                for x in 0..<world.width {
                    let coord = GridCoord(x: x, y: y, story: story)
                    let tile = world.tiles[story][y][x]
                    worldLayer.addChild(PlaceholderFactory.tileNode(for: tile, at: coord, config: config))
                }
            }
        }

        syncEntities(world.entities, anchor: anchor)
        updateWorldAnchor(anchor)
    }

    func syncEntities(_ entities: [GameEntity], anchor: GridCoord) {
        let playerEntity = entities.first(where: \.isPlayer)

        for entity in entities where !entity.isPlayer {
            if let node = entityNodes[entity.id] {
                PlaceholderFactory.updateEntityNode(
                    node,
                    entity: entity,
                    anchor: anchor,
                    viewCenter: viewCenter,
                    config: config
                )
            } else {
                let node = PlaceholderFactory.entityNode(for: entity, config: config)
                entityNodes[entity.id] = node
                entityLayer.addChild(node)
                PlaceholderFactory.updateEntityNode(
                    node,
                    entity: entity,
                    anchor: anchor,
                    viewCenter: viewCenter,
                    config: config
                )
            }
        }

        if let playerEntity {
            if playerNode == nil {
                let node = PlaceholderFactory.entityNode(for: playerEntity, config: config)
                playerNode = node
                playerLayer.addChild(node)
            }
            playerNode?.position = viewCenter
            playerNode?.zPosition = IsometricMath.depthSortValue(for: playerEntity.position, config: config) + 0.5
        }
    }

    func updateWorldAnchor(_ anchor: GridCoord) {
        worldRoot.position = IsometricMath.worldRootOffset(
            anchor: anchor,
            viewCenter: viewCenter,
            config: config
        )
        playerNode?.position = viewCenter
    }

    func applyAnimation(to entities: [GameEntity], frame: Int) {
        if let player = entities.first(where: \.isPlayer), let node = playerNode {
            PlaceholderFactory.applyAnimationFrame(frame, to: node)
        }

        for entity in entities where !entity.isPlayer {
            guard let node = entityNodes[entity.id] else { continue }
            PlaceholderFactory.applyAnimationFrame(frame, to: node)
        }
    }

    var sceneViewCenter: CGPoint {
        viewCenter
    }
}
