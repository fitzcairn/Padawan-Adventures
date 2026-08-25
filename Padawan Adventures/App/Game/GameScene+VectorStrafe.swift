import SpriteKit

extension GameScene {
    static let vectorFadeInDuration: TimeInterval = 0.5
    static let vectorFlightDuration: TimeInterval = 2.6
    static let vectorFadeOutDuration: TimeInterval = 0.5
    static let vectorBoltDuration: TimeInterval = 0.55

    /// Strafes NE→SW across the camera and bolts every enemy currently on screen.
    func performVectorStrafe(completion: ((Int) -> Void)? = nil) {
        isPausedForEncounter = true
        pendingInput = PendingInput()
        movement.reset()

        let targets = VectorStrafeUse.visibleEnemies(
            in: world,
            shownFloorCells: renderer.visibility.floorCells,
            focus: viewportFocus,
            viewCenter: renderer.sceneViewCenter,
            viewSize: renderer.viewSize,
            scale: renderer.worldScale,
            config: isoConfig
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            let killed = await self.runVectorStrafe(targets: targets)
            self.captureContinueAndSave()
            self.isPausedForEncounter = false
            completion?(killed)
        }
    }

    private func runVectorStrafe(targets: [GameEntity]) async -> Int {
        let path = vectorFlightPath()
        let heading = atan2(path.end.y - path.start.y, path.end.x - path.start.x)

        await fadeVectorLoop(from: 0.02, to: 1, duration: Self.vectorFadeInDuration)

        let ship = VectorStrafeVFX.makeShip()
        ship.position = path.start
        ship.zRotation = heading
        ship.zPosition = 20_000_000
        addChild(ship)

        var killed = 0
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { @MainActor in
                await self.animateVectorShip(ship, from: path.start, to: path.end)
                return false
            }
            for target in targets {
                let progress = VectorStrafeUse.fireProgress(
                    from: path.start,
                    to: path.end,
                    target: self.vectorScenePoint(for: target)
                )
                group.addTask { @MainActor in
                    await self.fireVectorBolt(
                        at: target,
                        path: path,
                        fireProgress: progress
                    )
                }
            }
            for await didKill in group where didKill {
                killed += 1
            }
        }

        ship.removeFromParent()
        await fadeVectorLoop(from: 1, to: 0.02, duration: Self.vectorFadeOutDuration)
        SoundEffectsController.shared.stopLoop(trackID: playerFx.trackID(for: "vector"))
        return killed
    }

    private func animateVectorShip(_ ship: SKNode, from start: CGPoint, to end: CGPoint) async {
        let grounded = renderer.worldRoot.position
        let frameSeconds: TimeInterval = 1.0 / 60.0
        let steps = max(2, Int(Self.vectorFlightDuration / frameSeconds))
        VectorStrafeHaptics.playFlyover(duration: Self.vectorFlightDuration)
        defer {
            renderer.worldRoot.position = grounded
            VectorStrafeHaptics.stop()
        }
        for step in 1...steps {
            if Task.isCancelled { return }
            let t = CGFloat(step) / CGFloat(steps)
            ship.position = CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
            let boom = sin(t * .pi)
            let amplitude = 18 * boom
            renderer.worldRoot.position = CGPoint(
                x: grounded.x + CGFloat.random(in: -amplitude...amplitude),
                y: grounded.y + CGFloat.random(in: -amplitude...amplitude)
            )
            try? await Task.sleep(nanoseconds: UInt64(frameSeconds * 1_000_000_000))
        }
        ship.position = end
    }

    private func fireVectorBolt(
        at target: GameEntity,
        path: (start: CGPoint, end: CGPoint),
        fireProgress: CGFloat
    ) async -> Bool {
        let delay = Self.vectorFlightDuration * TimeInterval(fireProgress)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        guard world.entity(id: target.id)?.isEnemy == true else { return false }

        let origin = vectorPointOnPath(path, progress: fireProgress)
        let destination = vectorImpactPoint(for: target)
        SoundEffectsController.shared.play(event: "vector_shoot", from: playerFx)

        let bolt = VectorStrafeVFX.makeBolt()
        bolt.position = origin
        bolt.zRotation = atan2(destination.y - origin.y, destination.x - origin.x)
        bolt.zPosition = 20_000_100
        addChild(bolt)

        let frameSeconds: TimeInterval = 1.0 / 60.0
        let steps = max(2, Int(Self.vectorBoltDuration / frameSeconds))
        for step in 1...steps {
            if Task.isCancelled { break }
            let t = CGFloat(step) / CGFloat(steps)
            bolt.position = CGPoint(
                x: origin.x + (destination.x - origin.x) * t,
                y: origin.y + (destination.y - origin.y) * t
            )
            try? await Task.sleep(nanoseconds: UInt64(frameSeconds * 1_000_000_000))
        }
        bolt.removeFromParent()

        guard world.entity(id: target.id)?.isEnemy == true else { return false }
        SoundEffectsController.shared.play(event: "vector_hit", from: playerFx)
        VectorStrafeVFX.playExplosion(in: self, at: destination)
        simulationLoop.removeEnemy(id: target.id, from: &world)
        renderer.playEnemyDefeatAnimation(id: target.id) {}
        return true
    }

    private func fadeVectorLoop(from start: Float, to end: Float, duration: TimeInterval) async {
        let steps = max(2, Int(duration / 0.04))
        for step in 1...steps {
            if Task.isCancelled { return }
            let t = Float(step) / Float(steps)
            SoundEffectsController.shared.startLoop(
                event: "vector",
                from: playerFx,
                volumeScale: start + (end - start) * t
            )
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    private func vectorFlightPath() -> (start: CGPoint, end: CGPoint) {
        let size = renderer.viewSize == .zero ? self.size : renderer.viewSize
        let anchor: CGPoint
        if let player = world.entities.first(where: \.isPlayer),
           let node = renderer.entityNode(id: player.id) {
            anchor = node.convert(.zero, to: self)
        } else {
            anchor = renderer.sceneViewCenter
        }
        return VectorStrafeUse.flightPath(
            through: anchor,
            viewSize: size,
            config: isoConfig,
            scale: renderer.worldScale,
            offscreenPadding: VectorStrafeVFX.shipLength * 0.7
        )
    }

    private func vectorPointOnPath(
        _ path: (start: CGPoint, end: CGPoint),
        progress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: path.start.x + (path.end.x - path.start.x) * progress,
            y: path.start.y + (path.end.y - path.start.y) * progress
        )
    }

    private func vectorScenePoint(for entity: GameEntity) -> CGPoint {
        if let node = renderer.entityNode(id: entity.id) {
            return node.convert(.zero, to: self)
        }
        return IsometricMath.viewPosition(
            worldPoint: IsometricMath.entityScreenPosition(entity.position, config: isoConfig),
            focus: viewportFocus,
            viewCenter: renderer.sceneViewCenter,
            scale: renderer.worldScale
        )
    }

    /// Top-center of the enemy sprite in scene space (fallback: standing point).
    private func vectorImpactPoint(for entity: GameEntity) -> CGPoint {
        guard let node = renderer.entityNode(id: entity.id) else {
            return vectorScenePoint(for: entity)
        }
        let frame = node.calculateAccumulatedFrame()
        let topInParent = CGPoint(x: frame.midX, y: frame.maxY)
        if let parent = node.parent {
            return parent.convert(topInParent, to: self)
        }
        return node.convert(CGPoint(x: 0, y: frame.maxY - node.position.y), to: self)
    }
}
