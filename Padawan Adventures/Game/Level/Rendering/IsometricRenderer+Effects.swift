import SpriteKit

extension IsometricRenderer {
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
            timingNode: worldRoot
        ) { [weak self] in
            self?.dissolvingGateOccluders.removeAll()
            completion()
        }
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

    func fadeWorld(duration: TimeInterval = WorldFade.duration, completion: @escaping () -> Void) {
        fadeWorldOut(duration: duration, completion: completion)
    }

    func fadeWorldOut(duration: TimeInterval = WorldFade.duration, completion: @escaping () -> Void) {
        worldRoot.removeAction(forKey: "worldFade")
        worldRoot.run(.sequence([
            .fadeOut(withDuration: duration),
            .run(completion),
        ]), withKey: "worldFade")
    }

    func fadeWorldIn(duration: TimeInterval = WorldFade.duration, completion: @escaping () -> Void) {
        worldRoot.removeAction(forKey: "worldFade")
        worldRoot.alpha = 0
        worldRoot.isHidden = false
        worldRoot.run(.sequence([
            .fadeIn(withDuration: duration),
            .run(completion),
        ]), withKey: "worldFade")
    }

    /// Green/blue particle swirl on the tapped floor tile (tap-to-move destination).
    func playTapTarget(at coord: GridCoord) {
        let position: CGPoint
        if let floorNode = floorNodes[coord] {
            position = CGPoint(
                x: floorNode.position.x,
                y: floorNode.position.y - config.tileHeight * 0.5
            )
        } else {
            position = IsometricMath.entityScreenPosition(coord, config: config)
        }

        let floorZ = IsometricMath.effectiveFloorZ(for: coord, config: config)
        let startZ = floorZ + TapTargetSwirl.floorOverlayZ
        let playerZ = IsometricMath.effectiveEntityZ(for: coord, config: config)
        let reticuleZ = TapTargetSwirl.reticuleLocalZ(
            startZ: startZ,
            at: coord,
            gates: entityGateOccluders,
            config: config
        )

        TapTargetSwirl.play(
            in: worldRoot,
            at: position,
            startZ: startZ,
            playerZ: playerZ,
            tileWidth: config.tileWidth,
            tileHeight: config.tileHeight,
            playerSpriteHeight: playerSpriteDisplayHeight,
            reticuleZ: reticuleZ
        )
    }

    /// Live player sprite height, or the configured / placeholder height before the node exists.
    var playerSpriteDisplayHeight: CGFloat {
        if let player = entityNodes.values.first(where: { $0.name == "player" }) {
            let height = player.calculateAccumulatedFrame().height
            if height > 1 { return height }
        }
        return PlaceholderFactory.playerDisplayHeight(
            isoConfig: config,
            spriteConfig: playerSpriteConfig
        )
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
}
