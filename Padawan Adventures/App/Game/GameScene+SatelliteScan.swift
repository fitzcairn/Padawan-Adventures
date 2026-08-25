import SpriteKit

extension GameScene {
    static let satelliteCameraDuration: TimeInterval = 0.9
    static let satelliteRingDuration: TimeInterval = 0.32
    static let satelliteHoldDuration: TimeInterval = 3.0

    private static let scanSparkle = HighlightConfig(
        color: "#7FDBFF",
        birthRate: 36,
        lifetime: 0.65,
        radius: 0.75,
        particleSize: 0.12,
        alpha: 0.92,
        yOffset: 0.2
    )

    /// Zooms to the artifact, reveals a 5-tile radius outward, then returns to the player.
    func performSatelliteScan(at origin: GridCoord, completion: @escaping () -> Void) {
        isPausedForEncounter = true
        pendingInput = PendingInput()
        movement.reset()
        tutorialOwnsCamera = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            let loopID = SoundEffectsController.shared.startLoop(event: "scan", from: self.playerFx)
            await self.animateCamera(
                to: IsometricMath.entityScreenPosition(origin, config: self.isoConfig),
                scale: self.satelliteScanScale(around: origin),
                duration: Self.satelliteCameraDuration
            )
            await self.revealSatelliteRings(from: origin)
            SoundEffectsController.shared.stopLoop(trackID: loopID)
            self.captureContinueAndSave()
            try? await Task.sleep(nanoseconds: UInt64(Self.satelliteHoldDuration * 1_000_000_000))
            let player = self.world.playerPosition ?? self.world.spawn
            await self.animateCamera(
                to: IsometricMath.entityScreenPosition(player, config: self.isoConfig),
                scale: 1,
                duration: Self.satelliteCameraDuration
            )
            self.tutorialOwnsCamera = false
            self.viewportCamera.snapToFollowing()
            self.isPausedForEncounter = false
            completion()
        }
    }

    private func satelliteScanScale(around origin: GridCoord) -> CGFloat {
        let span = SatelliteScanUse.radius * 2 + 1
        let bounds = IsometricMath.mapScreenBounds(
            width: span,
            height: span,
            story: origin.story,
            config: isoConfig
        )
        let fitted = IsometricMath.fitScale(
            mapBounds: bounds,
            viewSize: renderer.viewSize,
            margin: 0.1
        )
        return min(max(fitted, 0.35), 0.85)
    }

    private func animateCamera(to focus: CGPoint, scale: CGFloat, duration: TimeInterval) async {
        let startFocus = viewportFocus
        let startScale = renderer.worldScale
        let frameSeconds: TimeInterval = 1.0 / 60.0
        let steps = max(2, Int(duration / frameSeconds))
        for step in 1...steps {
            if Task.isCancelled { return }
            let progress = CGFloat(step) / CGFloat(steps)
            renderer.lockWorldScale(startScale + (scale - startScale) * smoothstep(progress))
            setViewportFocus(IsometricMath.interpolatedFocus(
                from: startFocus,
                to: focus,
                progress: progress
            ))
            try? await Task.sleep(nanoseconds: UInt64(frameSeconds * 1_000_000_000))
        }
        renderer.lockWorldScale(scale)
        setViewportFocus(focus)
    }

    private func revealSatelliteRings(from origin: GridCoord) async {
        for distance in 0...SatelliteScanUse.radius {
            if Task.isCancelled { return }
            let ring = SatelliteScanUse.ring(origin: origin, distance: distance, in: world)
            let floors = SatelliteScanUse.floorsToReveal(
                origin: origin,
                distance: distance,
                in: world
            )
            if !floors.isEmpty {
                renderer.armRevealFade()
                world.revealScannedFloors(floors)
                renderer.render(world: world, focus: viewportFocus)
                fadeInSatelliteNodes(renderer.takeRevealedNodes(), duration: Self.satelliteRingDuration)
            }
            playSatelliteSparkles(at: ring)
            try? await Task.sleep(nanoseconds: UInt64(Self.satelliteRingDuration * 1_000_000_000))
        }
    }

    private func fadeInSatelliteNodes(_ nodes: [SKNode], duration: TimeInterval) {
        for node in nodes {
            node.alpha = 0
            node.run(.fadeIn(withDuration: duration))
        }
    }

    private func playSatelliteSparkles(at coords: [GridCoord]) {
        let height = max(isoConfig.tileHeight * 1.3, 36)
        let linger = max(Self.scanSparkle.lifetime * 1.6, 0.7)
        for coord in coords {
            let burst = SparkleEmitterFactory.makeBurstNode(
                config: Self.scanSparkle,
                referenceHeight: height,
                particleCount: 10
            )
            burst.position = IsometricMath.entityScreenPosition(coord, config: isoConfig)
            burst.zPosition = IsometricMath.effectiveEntityZ(for: coord, config: isoConfig) + 8
            renderer.worldRoot.addChild(burst)
            burst.run(.sequence([
                .wait(forDuration: linger),
                .removeFromParent(),
            ]))
        }
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
