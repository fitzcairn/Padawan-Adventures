import SpriteKit
import UIKit

extension IsometricRenderer {
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
    func showsEntity(_ entity: GameEntity) -> Bool {
        entity.isPlayer || visibility.floorCells.contains(entity.position)
    }

    func applyRevealAlpha(to node: SKNode, entity: GameEntity) {
        guard !entity.isPlayer, revealFadeCells.contains(entity.position) else { return }
        node.alpha = 0
        revealFadeEntityIDs.insert(entity.id)
    }

    func updateEntityNode(_ node: SKNode, entity: GameEntity) {
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

    func enemySprite(for entity: GameEntity) -> (id: String, config: SpriteConfig)? {
        guard entity.isEnemy, let typeID = entity.enemyTypeID else { return nil }
        return enemyConfig.spriteConfig(for: typeID)
    }

    func enemyAnimatedSprite(id: UUID) -> AnimatedSpriteNode? {
        entityNodes[id]?.childNode(withName: AnimatedSpriteNode.nodeName) as? AnimatedSpriteNode
    }
    func fillColor(for entity: GameEntity) -> UIColor {
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
