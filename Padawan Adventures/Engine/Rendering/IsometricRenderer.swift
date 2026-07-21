import SpriteKit

final class IsometricRenderer {
    private let config: IsometricConfig
    private let worldRoot = SKNode()
    /// Floor / ramp / slide tiles — always beneath sprites.
    private let floorLayer = SKNode()
    /// Walls and entities share this layer so walls can occlude sprites by depth.
    private let occlusionLayer = SKNode()
    private var entityNodes: [UUID: SKNode] = [:]
    private var viewCenter: CGPoint = .zero
    private var viewportFocus: CGPoint = .zero
    /// Only this story's tiles/entities are drawn.
    private(set) var visibleStory: Int = 0

    init(config: IsometricConfig = IsometricConfig()) {
        self.config = config
    }

    func attach(to scene: SKScene) {
        worldRoot.removeAllChildren()
        floorLayer.removeAllChildren()
        occlusionLayer.removeAllChildren()
        entityNodes.removeAll()
        visibleStory = 0

        viewCenter = CGPoint(
            x: scene.size.width * (0.5 - scene.anchorPoint.x),
            y: scene.size.height * (0.5 - scene.anchorPoint.y)
        )

        floorLayer.zPosition = 0
        occlusionLayer.zPosition = 1

        worldRoot.addChild(floorLayer)
        worldRoot.addChild(occlusionLayer)
        scene.addChild(worldRoot)
    }

    func render(world: GameWorld, focus: CGPoint) {
        visibleStory = world.playerPosition?.story ?? world.spawn.story

        // Keep entity nodes; only rebuild tiles.
        let preservedEntities = Dictionary(uniqueKeysWithValues: entityNodes.map { ($0.key, $0.value) })
        for node in preservedEntities.values {
            node.removeFromParent()
        }

        floorLayer.removeAllChildren()
        occlusionLayer.removeAllChildren()
        entityNodes = preservedEntities

        let story = visibleStory
        guard story >= 0, story < world.storyCount else {
            syncEntities(world.entities)
            updateViewportFocus(focus)
            return
        }

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                let node = PlaceholderFactory.tileNode(for: tile, at: coord, in: world, config: config)

                switch tile.kind {
                case .wall:
                    node.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                    occlusionLayer.addChild(node)
                case .floor, .ramp, .slide:
                    node.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                    floorLayer.addChild(node)
                }
            }
        }

        syncEntities(world.entities)
        updateViewportFocus(focus)
    }

    /// Rebuilds tiles if the player moved to a different story.
    @discardableResult
    func updateVisibleStory(for world: GameWorld, focus: CGPoint) -> Bool {
        let story = world.playerPosition?.story ?? world.spawn.story
        guard story != visibleStory else { return false }
        render(world: world, focus: focus)
        return true
    }

    func syncEntities(_ entities: [GameEntity]) {
        let liveIDs = Set(entities.map(\.id))
        for id in entityNodes.keys where !liveIDs.contains(id) {
            entityNodes[id]?.removeFromParent()
            entityNodes[id] = nil
        }

        for entity in entities {
            let onVisibleStory = entity.position.story == visibleStory
            if let node = entityNodes[entity.id] {
                if onVisibleStory {
                    if node.parent !== occlusionLayer {
                        node.removeFromParent()
                        occlusionLayer.addChild(node)
                    }
                    PlaceholderFactory.updateEntityNode(node, entity: entity, config: config)
                } else {
                    node.removeFromParent()
                }
            } else if onVisibleStory {
                let node = PlaceholderFactory.entityNode(for: entity, config: config)
                entityNodes[entity.id] = node
                occlusionLayer.addChild(node)
                PlaceholderFactory.updateEntityNode(node, entity: entity, config: config)
            }
        }
    }

    func updateViewportFocus(_ focus: CGPoint) {
        viewportFocus = focus
        worldRoot.position = IsometricMath.worldRootOffset(
            focus: focus,
            viewCenter: viewCenter
        )
    }

    func updateEntityDisplayPosition(_ entity: GameEntity, at gridCoord: GridCoord) {
        updateEntityDisplayPosition(
            entity,
            screenPosition: IsometricMath.entityScreenPosition(gridCoord, config: config),
            sortCoord: gridCoord
        )
    }

    /// Places an entity at a continuous screen position while sorting by occupancy tile.
    func updateEntityDisplayPosition(
        _ entity: GameEntity,
        screenPosition: CGPoint,
        sortCoord: GridCoord
    ) {
        guard let node = entityNodes[entity.id] else { return }
        node.position = screenPosition
        node.zPosition = IsometricMath.entitySortValue(for: sortCoord, config: config)
    }

    func applyAnimation(to entities: [GameEntity], frame: Int) {
        for entity in entities {
            guard let node = entityNodes[entity.id] else { continue }
            PlaceholderFactory.applyAnimationFrame(frame, to: node)
        }
    }

    var sceneViewCenter: CGPoint {
        viewCenter
    }

    var currentFocus: CGPoint {
        viewportFocus
    }
}
