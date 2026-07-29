import SpriteKit

final class IsometricRenderer {
    private let config: IsometricConfig
    private let enemyConfig: EnemyConfig
    private let spriteLibrary: SpriteLibrary?
    private let playerSpriteConfig: SpriteConfig?
    private let itemsConfig: ItemsConfig?
    private let treasureItemID: String?
    private let floorTileSetLibrary: FloorTileSetLibrary?
    private let gateSpriteSetLibrary: GateSpriteSetLibrary?
    private let worldRoot = SKNode()
    /// Floor terrain — shared band with walls/entities; local z uses increasing grid Y.
    private let floorLayer = SKNode()
    /// Solid walls / ceilings — same occlusion band as entities (accumulated z interleaves).
    private let wallLayer = SKNode()
    /// Players, enemies, pickups, effects, and gate sprites — siblings so gate occlusion
    /// applies equally to every entity type (not only the moving player).
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
    /// Canonical gate strips on the visible story — used for entity/gate occlusion.
    private var gateOccluders: [PlaceholderFactory.GateOccluder] = []
    /// Rooms the player can reach without crossing a closed gate; everything else is dark.
    private var visibility: RoomVisibility.Result = .empty
    /// Cells revealed by the latest render that are waiting to be faded in.
    private var revealFadeCells: Set<GridCoord> = []
    /// Entities inside `revealFadeCells`, held so their nodes fade in with the room.
    private var revealFadeEntityIDs: Set<UUID> = []
    /// Set by `armRevealFade()` so only a gate opening fades its new room in.
    private var fadesNextReveal = false
    /// Story the current `visibility` was computed for (`nil` before the first render).
    private var visibilityStory: Int?
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
        floorTileSetLibrary: FloorTileSetLibrary? = nil,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil
    ) {
        self.config = config
        self.enemyConfig = enemyConfig
        self.spriteLibrary = spriteLibrary
        self.playerSpriteConfig = playerSpriteConfig
        self.itemsConfig = itemsConfig
        self.treasureItemID = treasureItemID
        self.gateSpriteSetLibrary = gateSpriteSetLibrary
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
        gateOccluders = []
        visibility = .empty
        revealFadeCells.removeAll()
        revealFadeEntityIDs.removeAll()
        fadesNextReveal = false
        visibilityStory = nil
        visibleStory = 0
        worldScale = 1

        viewSize = scene.size
        viewCenter = CGPoint(
            x: scene.size.width * (0.5 - scene.anchorPoint.x),
            y: scene.size.height * (0.5 - scene.anchorPoint.y)
        )

        // Floors sit in a lower band so floor/decor art never covers sprites.
        // Walls and entities share the occlusion band and interleave by grid Y.
        floorLayer.zPosition = IsometricMath.floorBandBase
        wallLayer.zPosition = IsometricMath.occlusionBandBase
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
            visibility = .empty
            visibilityStory = nil
            revealFadeCells.removeAll()
            revealFadeEntityIDs.removeAll()
            fadesNextReveal = false
            clearFloorNodes()
            clearWallNodes()
            clearCeilingNodes()
            syncEntities(world.entities)
            updateViewportFocus(focus)
            return
        }

        updateVisibility(world: world, story: story)

        syncFloorNodes(world: world, story: story)
        syncWallNodes(world: world, story: story)
        syncCeilingNodes(world: world, story: story)

        syncEntities(world.entities)
        updateViewportFocus(focus)
    }

    /// Makes the next render's newly reachable rooms start hidden, so a gate opening can
    /// fade them in. Reveals from any other render (level start, restore) appear at once.
    func armRevealFade() {
        fadesNextReveal = true
    }

    private func updateVisibility(world: GameWorld, story: Int) {
        let previous = visibilityStory == story ? visibility.renderableCells : []
        visibility = RoomVisibility.compute(
            in: world,
            story: story,
            from: world.playerPosition ?? world.spawn
        )
        visibilityStory = story
        guard fadesNextReveal else { return }
        fadesNextReveal = false
        revealFadeCells = visibility.renderableCells.subtracting(previous)
        revealFadeEntityIDs.removeAll()
    }

    /// True when a cell is inside a reachable room (its floor art may draw).
    private func showsFloor(at coord: GridCoord) -> Bool {
        visibility.floorCells.contains(coord)
    }

    /// True when a wall/gate cell borders a reachable room (a sealing gate stays visible).
    private func showsWall(at coord: GridCoord) -> Bool {
        visibility.renderableCells.contains(coord)
    }

    /// Newly revealed art starts invisible so `playGateOpenAnimation` can fade it in.
    private func applyRevealAlpha(to node: SKNode, at coord: GridCoord) {
        guard revealFadeCells.contains(coord) else { return }
        node.alpha = 0
    }

    /// Reuses base floor sprite nodes when terrain identity is unchanged.
    private func syncFloorNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                guard case .floor = tile.kind,
                      showsFloor(at: coord),
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
                applyRevealAlpha(to: node, at: coord)
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
    /// Gates are parented under `occlusionLayer` with entities so pickup/player/enemy
    /// z adjustments can win or lose against the gate sprite as siblings.
    private func syncWallNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()
        // Culled gates draw nothing, so they must not reorder entities either.
        gateOccluders = PlaceholderFactory.gateOccluders(in: world, story: story).filter {
            showsWall(at: $0.cell) || showsWall(at: $0.partner)
        }

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                guard showsWall(at: coord) else { continue }
                guard let identity = PlaceholderFactory.wallIdentity(
                    for: tile,
                    at: coord,
                    in: world,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                ) else {
                    continue
                }
                liveCoords.insert(coord)

                let sortCoord = PlaceholderFactory.wallSortCoord(for: tile, at: coord, in: world) ?? coord
                let screen = PlaceholderFactory.wallScreenPosition(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                ) ?? IsometricMath.gridToScreen(coord, config: config)
                let parentLayer = occlusionParent(for: tile)

                if let existing = wallNodes[coord], wallIdentities[coord] == identity {
                    if existing.parent !== parentLayer {
                        existing.removeFromParent()
                        parentLayer.addChild(existing)
                    }
                    existing.position = screen
                    existing.zPosition = IsometricMath.wallSortValue(for: sortCoord, config: config)
                    continue
                }

                wallNodes[coord]?.removeFromParent()
                let node = PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    floorTileSetLibrary: floorTileSetLibrary,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                )
                node.zPosition = IsometricMath.wallSortValue(for: sortCoord, config: config)
                applyRevealAlpha(to: node, at: coord)
                parentLayer.addChild(node)
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

    /// Gates share the entity layer; ordinary walls stay on `wallLayer`.
    private func occlusionParent(for tile: Tile) -> SKNode {
        if case .gate = tile.kind { return occlusionLayer }
        return wallLayer
    }

    /// Reuses ceiling diamonds when a cell still needs a roof overlay.
    private func syncCeilingNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard showsWall(at: coord) else { continue }
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
                applyRevealAlpha(to: ceiling, at: coord)
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
        gateOccluders = []
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
            let shows = entity.position.story == visibleStory && showsEntity(entity)
            if let node = entityNodes[entity.id] {
                if shows {
                    if node.parent !== occlusionLayer {
                        node.removeFromParent()
                        applyRevealAlpha(to: node, entity: entity)
                        occlusionLayer.addChild(node)
                    }
                    updateEntityNode(node, entity: entity)
                } else {
                    node.removeFromParent()
                }
            } else if shows {
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
                applyRevealAlpha(to: node, entity: entity)
                occlusionLayer.addChild(node)
                updateEntityNode(node, entity: entity)
            }
        }
    }

    /// Enemies and pickups stay hidden until their room is reachable; the player always draws.
    private func showsEntity(_ entity: GameEntity) -> Bool {
        entity.isPlayer || visibility.floorCells.contains(entity.position)
    }

    private func applyRevealAlpha(to node: SKNode, entity: GameEntity) {
        guard !entity.isPlayer, revealFadeCells.contains(entity.position) else { return }
        node.alpha = 0
        revealFadeEntityIDs.insert(entity.id)
    }

    private func updateEntityNode(_ node: SKNode, entity: GameEntity) {
        PlaceholderFactory.updateEntityNode(
            node,
            entity: entity,
            config: config,
            gates: gateOccluders
        )
    }

    func entityNode(id: UUID) -> SKNode? {
        entityNodes[id]
    }

    /// Detaches a pickup node from sync so a collect animation can finish.
    func detachEntityNode(id: UUID) -> SKNode? {
        guard let node = entityNodes.removeValue(forKey: id) else { return nil }
        return node
    }

    /// Detaches a wall/gate node from sync so an open animation can finish.
    func detachWallNode(at coord: GridCoord) -> SKNode? {
        wallIdentities[coord] = nil
        return wallNodes.removeValue(forKey: coord)
    }

    /// Detaches the visible gate sprite for the strip containing `coord`, if any.
    func detachGateNode(at coord: GridCoord, in world: GameWorld) -> SKNode? {
        guard case .gate(let minigame) = world.tile(at: coord)?.kind else {
            return detachWallNode(at: coord)
        }
        if let strip = PlaceholderFactory.gateStrip(at: coord, minigame: minigame, in: world) {
            let canonical = strip.isCanonical ? coord : strip.partner
            if let node = detachWallNode(at: canonical) { return node }
            if let node = detachWallNode(at: strip.partner) { return node }
        }
        return detachWallNode(at: coord)
    }

    /// Sets alpha on floor nodes at `coords` (no-op for missing nodes).
    func setFloorNodesAlpha(_ alpha: CGFloat, at coords: [GridCoord]) {
        for coord in coords {
            floorNodes[coord]?.alpha = alpha
        }
    }

    func floorNodes(at coords: [GridCoord]) -> [SKNode] {
        coords.compactMap { floorNodes[$0] }
    }

    /// Nodes for cells the armed render revealed, handed over once so a later render does
    /// not blank them again.
    func takeRevealedNodes() -> [SKNode] {
        var nodes: [SKNode] = []
        for coord in revealFadeCells {
            if let node = floorNodes[coord] { nodes.append(node) }
            if let node = wallNodes[coord] { nodes.append(node) }
            if let node = ceilingNodes[coord] { nodes.append(node) }
        }
        nodes.append(contentsOf: revealFadeEntityIDs.compactMap { entityNodes[$0] })
        revealFadeCells.removeAll()
        revealFadeEntityIDs.removeAll()
        return nodes
    }

    /// Gate sparkle dissolve + connecting floor fade-in (see `PlaceholderFactory.gateOpenDuration`).
    /// The room the gate was sealing fades in on the same beat.
    func playGateOpenAnimation(
        gateNode: SKNode?,
        floorCoords: [GridCoord],
        completion: @escaping () -> Void
    ) {
        let revealed = floorNodes(at: floorCoords) + takeRevealedNodes()
        let referenceHeight: CGFloat
        if let gateNode {
            let frame = gateNode.calculateAccumulatedFrame()
            referenceHeight = max(frame.height, config.wallHeight * 2)
        } else {
            referenceHeight = config.wallHeight * 2
        }
        PlaceholderFactory.playGateOpenAnimation(
            on: gateNode,
            revealNodes: revealed,
            referenceHeight: referenceHeight,
            timingNode: worldRoot,
            completion: completion
        )
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

    /// Detaches an enemy node and plays the red-sparkle defeat fade.
    func playEnemyDefeatAnimation(id: UUID, completion: @escaping () -> Void) {
        guard let node = detachEntityNode(id: id) else {
            completion()
            return
        }
        PlaceholderFactory.playDefeatAnimation(on: node) {
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
            sortX: Double(gridCoord.x),
            sortY: Double(gridCoord.y),
            sortStory: gridCoord.story
        )
    }

    /// Places an entity at a continuous screen position, sorting by the same fractional
    /// grid pose used for drawing so floors under the sprite cannot win mid-move.
    /// Gate strips use axis-aware occlusion for players, enemies, and pickups:
    /// near-side poses draw above the gate; far-side poses draw below it.
    func updateEntityDisplayPosition(
        _ entity: GameEntity,
        screenPosition: CGPoint,
        sortX: Double,
        sortY: Double,
        sortStory: Int
    ) {
        guard let node = entityNodes[entity.id] else { return }
        node.position = screenPosition
        node.zPosition = PlaceholderFactory.entitySortValueAccountingForGates(
            x: sortX,
            y: sortY,
            story: sortStory,
            gates: gateOccluders,
            config: config
        )
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
