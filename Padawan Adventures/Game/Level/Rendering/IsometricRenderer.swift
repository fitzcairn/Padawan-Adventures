import SpriteKit

final class IsometricRenderer {
    private let config: IsometricConfig
    private let enemyConfig: EnemyConfig
    private let spriteLibrary: SpriteLibrary?
    private let playerSpriteConfig: SpriteConfig?
    private let itemsConfig: ItemsConfig?
    private let treasureItemID: String?
    private let floorTileSetLibrary: FloorTileSetLibrary?
    private let worldRoot = SKNode()
    /// Floor terrain — shared band with walls/entities; local z uses increasing grid Y.
    private let floorLayer = SKNode()
    /// Walls / ceilings — same parent band as floors so Y-order can cover either way.
    private let wallLayer = SKNode()
    /// Players, enemies, pickups, effects — same band; +0.5 above same-cell tiles.
    private let occlusionLayer = SKNode()
    private var entityNodes: [UUID: SKNode] = [:]
    /// Stable floor nodes keyed by grid coord so animations are not restarted each render.
    private var floorNodes: [GridCoord: SKNode] = [:]
    private var floorIdentities: [GridCoord: String] = [:]
    /// Stable wall / gate block nodes keyed by grid coord.
    private var wallNodes: [GridCoord: SKNode] = [:]
    private var wallIdentities: [GridCoord: String] = [:]
    /// Stable ceiling diamonds keyed by grid coord.
    private var ceilingNodes: [GridCoord: SKNode] = [:]
    private var ceilingIdentities: [GridCoord: String] = [:]
    private var viewCenter: CGPoint = .zero
    private var viewportFocus: CGPoint = .zero
    private var viewSize: CGSize = .zero
    /// Only this story's tiles/entities are drawn.
    private(set) var visibleStory: Int = 0
    /// Uniform scale applied to `worldRoot` (fit-to-view).
    private(set) var worldScale: CGFloat = 1

    init(
        config: IsometricConfig = IsometricConfig(),
        enemyConfig: EnemyConfig = .fallback,
        spriteLibrary: SpriteLibrary? = nil,
        playerSpriteConfig: SpriteConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        treasureItemID: String? = nil,
        floorTileSetLibrary: FloorTileSetLibrary? = nil
    ) {
        self.config = config
        self.enemyConfig = enemyConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.itemsConfig = itemsConfig
        self.treasureItemID = treasureItemID
        self.floorTileSetLibrary = floorTileSetLibrary
    }

    func attach(to scene: SKScene) {
        worldRoot.removeFromParent()
        worldRoot.removeAllChildren()
        floorLayer.removeAllChildren()
        wallLayer.removeAllChildren()
        occlusionLayer.removeAllChildren()
        entityNodes.removeAll()
        floorNodes.removeAll()
        floorIdentities.removeAll()
        wallNodes.removeAll()
        wallIdentities.removeAll()
        ceilingNodes.removeAll()
        ceilingIdentities.removeAll()
        visibleStory = 0
        worldScale = 1

        viewSize = scene.size
        viewCenter = CGPoint(
            x: scene.size.width * (0.5 - scene.anchorPoint.x),
            y: scene.size.height * (0.5 - scene.anchorPoint.y)
        )

        // Shared parent band: floors, walls, and entities interleave by increasing grid Y.
        // Accents are a sibling added after bases so they paint above base floor art.
        floorLayer.zPosition = IsometricMath.floorBandBase
        wallLayer.zPosition = IsometricMath.floorBandBase
        occlusionLayer.zPosition = IsometricMath.occlusionBandBase

        worldRoot.addChild(floorLayer)
        worldRoot.addChild(wallLayer)
        worldRoot.addChild(occlusionLayer)
        scene.addChild(worldRoot)
    }

    func render(world: GameWorld, focus: CGPoint) {
        visibleStory = world.playerPosition?.story ?? world.spawn.story

        let story = visibleStory
        guard story >= 0, story < world.storyCount else {
            clearFloorNodes()
            clearWallNodes()
            clearCeilingNodes()
            syncEntities(world.entities)
            updateViewportFocus(focus)
            return
        }

        syncFloorNodes(world: world, story: story)
        syncWallNodes(world: world, story: story)
        syncCeilingNodes(world: world, story: story)

        syncEntities(world.entities)
        updateViewportFocus(focus)
    }

    /// Reuses base floor sprite nodes when terrain identity is unchanged.
    private func syncFloorNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                guard case .floor = tile.kind,
                      let identity = PlaceholderFactory.floorIdentity(for: tile) else {
                    continue
                }
                liveCoords.insert(coord)

                if let existing = floorNodes[coord], floorIdentities[coord] == identity {
                    if existing.parent !== floorLayer {
                        existing.removeFromParent()
                        floorLayer.addChild(existing)
                    }
                    existing.position = PlaceholderFactory.floorScreenPosition(
                        for: tile,
                        at: coord,
                        config: config
                    )
                    existing.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                    continue
                }

                floorNodes[coord]?.removeFromParent()
                let node = PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    floorTileSetLibrary: floorTileSetLibrary
                )
                node.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                floorLayer.addChild(node)
                floorNodes[coord] = node
                floorIdentities[coord] = identity
            }
        }

        for coord in floorNodes.keys where !liveCoords.contains(coord) {
            floorNodes[coord]?.removeFromParent()
            floorNodes[coord] = nil
            floorIdentities[coord] = nil
        }
    }


    private func clearFloorNodes() {
        for node in floorNodes.values {
            node.removeFromParent()
        }
        floorNodes.removeAll()
        floorIdentities.removeAll()
    }


    /// Reuses wall / gate block nodes when kind, destructible flag, and faces are unchanged.
    private func syncWallNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                guard let identity = PlaceholderFactory.wallIdentity(for: tile, at: coord, in: world) else {
                    continue
                }
                liveCoords.insert(coord)

                if let existing = wallNodes[coord], wallIdentities[coord] == identity {
                    if existing.parent !== wallLayer {
                        existing.removeFromParent()
                        wallLayer.addChild(existing)
                    }
                    existing.position = IsometricMath.gridToScreen(coord, config: config)
                    existing.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                    continue
                }

                wallNodes[coord]?.removeFromParent()
                let node = PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config
                )
                node.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                wallLayer.addChild(node)
                wallNodes[coord] = node
                wallIdentities[coord] = identity
            }
        }

        for coord in wallNodes.keys where !liveCoords.contains(coord) {
            wallNodes[coord]?.removeFromParent()
            wallNodes[coord] = nil
            wallIdentities[coord] = nil
        }
    }

    /// Reuses ceiling diamonds when a cell still needs a roof overlay.
    private func syncCeilingNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard let identity = PlaceholderFactory.ceilingIdentity(at: coord, in: world) else {
                    continue
                }
                liveCoords.insert(coord)

                if let existing = ceilingNodes[coord], ceilingIdentities[coord] == identity {
                    if existing.parent !== wallLayer {
                        existing.removeFromParent()
                        wallLayer.addChild(existing)
                    }
                    existing.position = IsometricMath.gridToScreen(coord, config: config)
                    existing.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                    continue
                }

                ceilingNodes[coord]?.removeFromParent()
                let ceiling = PlaceholderFactory.ceilingNode(config: config)
                ceiling.position = IsometricMath.gridToScreen(coord, config: config)
                ceiling.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                wallLayer.addChild(ceiling)
                ceilingNodes[coord] = ceiling
                ceilingIdentities[coord] = identity
            }
        }

        for coord in ceilingNodes.keys where !liveCoords.contains(coord) {
            ceilingNodes[coord]?.removeFromParent()
            ceilingNodes[coord] = nil
            ceilingIdentities[coord] = nil
        }
    }

    private func clearWallNodes() {
        for node in wallNodes.values {
            node.removeFromParent()
        }
        wallNodes.removeAll()
        wallIdentities.removeAll()
    }

    private func clearCeilingNodes() {
        for node in ceilingNodes.values {
            node.removeFromParent()
        }
        ceilingNodes.removeAll()
        ceilingIdentities.removeAll()
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
                    fillColor: fillColor(for: entity),
                    spriteLibrary: spriteLibrary,
                    spriteConfig: entity.isPlayer ? playerSpriteConfig : nil,
                    itemsConfig: itemsConfig,
                    enemySprite: enemySprite(for: entity),
                    treasureItemID: treasureItemID
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
            // Real sprite sheets drive their own looping actions.
            if PlaceholderFactory.usesSpriteAnimation(node) { continue }
            PlaceholderFactory.applyAnimationFrame(frame, to: node)
        }
    }

    func playerAnimatedSprite() -> AnimatedSpriteNode? {
        guard let player = entityNodes.values.first(where: { $0.name == "player" }) else {
            return nil
        }
        return player.childNode(withName: AnimatedSpriteNode.nodeName) as? AnimatedSpriteNode
    }

    private func enemySprite(for entity: GameEntity) -> (id: String, config: SpriteConfig)? {
        guard entity.isEnemy, let typeID = entity.enemyTypeID else { return nil }
        return enemyConfig.spriteConfig(for: typeID)
    }

    func enemyAnimatedSprite(id: UUID) -> AnimatedSpriteNode? {
        entityNodes[id]?.childNode(withName: AnimatedSpriteNode.nodeName) as? AnimatedSpriteNode
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
