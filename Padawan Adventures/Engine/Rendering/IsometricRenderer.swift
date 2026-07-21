import SpriteKit

final class IsometricRenderer {
    private let config: IsometricConfig
    private let enemyConfig: EnemyConfig
    private let worldRoot = SKNode()
    /// Floor tiles — always beneath sprites.
    private let floorLayer = SKNode()
    /// Walls and entities share this layer so walls can occlude sprites by depth.
    private let occlusionLayer = SKNode()
    private var entityNodes: [UUID: SKNode] = [:]
    private var viewCenter: CGPoint = .zero
    private var viewportFocus: CGPoint = .zero
    private var viewSize: CGSize = .zero
    /// Only this story's tiles/entities are drawn.
    private(set) var visibleStory: Int = 0
    /// Uniform scale applied to `worldRoot` (fit-to-view).
    private(set) var worldScale: CGFloat = 1

    init(config: IsometricConfig = IsometricConfig(), enemyConfig: EnemyConfig = .fallback) {
        self.config = config
        self.enemyConfig = enemyConfig
    }

    func attach(to scene: SKScene) {
        worldRoot.removeFromParent()
        worldRoot.removeAllChildren()
        floorLayer.removeAllChildren()
        occlusionLayer.removeAllChildren()
        entityNodes.removeAll()
        visibleStory = 0
        worldScale = 1

        viewSize = scene.size
        viewCenter = CGPoint(
            x: scene.size.width * (0.5 - scene.anchorPoint.x),
            y: scene.size.height * (0.5 - scene.anchorPoint.y)
        )

        // SpriteKit adds parent+child zPositions: keep floors in a band that can never
        // overtake sprites even when a front floor has a large local sort value.
        floorLayer.zPosition = IsometricMath.floorBandBase
        occlusionLayer.zPosition = IsometricMath.occlusionBandBase

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
                case .wall(_, let hasDoor) where hasDoor:
                    // Door cells render as floor diamonds — keep them in the floor band.
                    node.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                    floorLayer.addChild(node)
                case .wall:
                    node.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                    occlusionLayer.addChild(node)
                case .floor:
                    node.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                    floorLayer.addChild(node)
                }
            }
        }

        // CEILING: gray wall-top diamonds over gaps / unrendered wall mass.
        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard IsometricTileGeometry.needsCeiling(at: coord, in: world) else { continue }
                let ceiling = PlaceholderFactory.ceilingNode(config: config)
                ceiling.position = IsometricMath.gridToScreen(coord, config: config)
                ceiling.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                occlusionLayer.addChild(ceiling)
            }
        }

        syncEntities(world.entities)
        updateViewportFocus(focus)
    }

    /// Locks uniform world scale (1 = native `IsometricConfig` tile size).
    func lockWorldScale(_ scale: CGFloat) {
        worldScale = scale
        updateViewportFocus(viewportFocus)
    }

    /// Scales and centers the viewport so the full grid on `story` fits in the scene.
    @discardableResult
    func fitMapInView(world: GameWorld, story: Int) -> CGPoint {
        let bounds = IsometricMath.mapScreenBounds(
            width: world.width,
            height: world.height,
            story: story,
            config: config
        )
        worldScale = IsometricMath.fitScale(mapBounds: bounds, viewSize: viewSize)
        let focus = IsometricMath.mapCenter(for: bounds)
        updateViewportFocus(focus)
        return focus
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
                let node = PlaceholderFactory.entityNode(
                    for: entity,
                    config: config,
                    fillColor: fillColor(for: entity)
                )
                entityNodes[entity.id] = node
                occlusionLayer.addChild(node)
                PlaceholderFactory.updateEntityNode(node, entity: entity, config: config)
            }
        }
    }

    func entityNode(id: UUID) -> SKNode? {
        entityNodes[id]
    }

    /// Detaches a pickup node from sync so a collect animation can finish.
    func detachEntityNode(id: UUID) -> SKNode? {
        guard let node = entityNodes.removeValue(forKey: id) else { return nil }
        return node
    }

    func playPickupCollectAnimation(id: UUID, completion: @escaping () -> Void) {
        guard let node = detachEntityNode(id: id) else {
            completion()
            return
        }
        PlaceholderFactory.playCollectAnimation(on: node) {
            node.removeFromParent()
            completion()
        }
    }

    func shakeWorld(duration: TimeInterval = 0.45, amplitude: CGFloat = 10, completion: @escaping () -> Void) {
        let base = worldRoot.position
        var steps: [SKAction] = []
        let stepDuration = 0.04
        let count = max(Int(duration / stepDuration), 1)
        for i in 0..<count {
            let t = CGFloat(i) / CGFloat(count)
            let falloff = 1 - t
            let dx = CGFloat.random(in: -amplitude...amplitude) * falloff
            let dy = CGFloat.random(in: -amplitude...amplitude) * falloff
            steps.append(.move(to: CGPoint(x: base.x + dx, y: base.y + dy), duration: stepDuration))
        }
        steps.append(.move(to: base, duration: stepDuration))
        steps.append(.run(completion))
        worldRoot.run(.sequence(steps), withKey: "worldShake")
    }

    func fadeWorld(duration: TimeInterval = 0.35, completion: @escaping () -> Void) {
        fadeWorldOut(duration: duration, completion: completion)
    }

    func fadeWorldOut(duration: TimeInterval = 0.35, completion: @escaping () -> Void) {
        worldRoot.removeAction(forKey: "worldFade")
        worldRoot.run(.sequence([
            .fadeOut(withDuration: duration),
            .run(completion),
        ]), withKey: "worldFade")
    }

    func fadeWorldIn(duration: TimeInterval = 0.35, completion: @escaping () -> Void) {
        worldRoot.removeAction(forKey: "worldFade")
        worldRoot.alpha = 0
        worldRoot.isHidden = false
        worldRoot.run(.sequence([
            .fadeIn(withDuration: duration),
            .run(completion),
        ]), withKey: "worldFade")
    }

    func updateViewportFocus(_ focus: CGPoint) {
        viewportFocus = focus
        worldRoot.setScale(worldScale)
        worldRoot.position = IsometricMath.worldRootOffset(
            focus: focus,
            viewCenter: viewCenter,
            scale: worldScale
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
        for entity in entities where !entity.isPickup {
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

    private func fillColor(for entity: GameEntity) -> UIColor {
        if entity.isPlayer {
            return PlaceholderFactory.playerFillColor
        }
        if let typeID = entity.enemyTypeID,
           let type = enemyConfig.type(named: typeID) {
            return type.fillColor
        }
        return PlaceholderFactory.defaultEntityFillColor
    }
}
