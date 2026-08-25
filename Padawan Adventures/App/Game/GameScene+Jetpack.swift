import SpriteKit

extension GameScene {
    static let jetpackJumpDuration: TimeInterval = JetpackJumpAnimation.duration

    /// Arc-jumps over a closed gate, then opens it in place (no world/HUD fade).
    func useJetpack(
        over gate: GridCoord,
        landing: GridCoord,
        completion: (() -> Void)? = nil
    ) {
        isPausedForEncounter = true
        pendingInput = PendingInput()
        movement.reset()

        guard let player = world.entities.first(where: \.isPlayer),
              let playerNode = renderer.entityNode(id: player.id)
        else {
            finishJetpackJump(gate: gate, landing: landing, completion: completion)
            return
        }

        let start = playerNode.position
        let end = IsometricMath.entityScreenPosition(landing, config: isoConfig)
        if let origin = world.playerPosition {
            playerFacing = CompassDirection.facing(from: origin, toward: landing)
        } else {
            playerFacing = end.x < start.x ? .left : .right
        }
        playJetpackSprite(facing: playerFacing)
        duckWorldMusicForJetpackJump()

        let arcHeight = max(
            isoConfig.wallHeight * 1.75,
            hypot(end.x - start.x, end.y - start.y) * 0.55
        )
        let control = CGPoint(
            x: (start.x + end.x) * 0.5,
            y: max(start.y, end.y) + arcHeight
        )
        let duration = Self.jetpackJumpDuration
        let action = SKAction.customAction(withDuration: duration) { [weak self] _, elapsedTime in
            guard let self else { return }
            let t = min(max(elapsedTime / CGFloat(duration), 0), 1)
            let point = PitArenaLayout.jumpPoint(
                t: t,
                start: start,
                control: control,
                end: end
            )
            playerNode.position = point
            let grid = IsometricMath.fractionalGridFromEntityScreen(
                point,
                story: landing.story,
                config: self.isoConfig
            )
            self.renderer.updateEntityDisplayPosition(
                player,
                screenPosition: point,
                sortX: grid.x,
                sortY: grid.y,
                sortStory: landing.story,
                ignoreGateOcclusion: true
            )
            self.viewportFocus = point
            self.renderer.updateViewportFocus(point)
        }
        playerNode.run(action) { [weak self] in
            playerNode.position = end
            self?.finishJetpackJump(gate: gate, landing: landing, completion: completion)
        }
    }

    private func playJetpackSprite(facing: CompassDirection) {
        guard let sprite = renderer.playerAnimatedSprite(),
              let library = spriteLibrary,
              let clip = library.animation(named: JetpackJumpAnimation.clipName(for: facing))
        else { return }

        let frameDuration = JetpackJumpAnimation.frameDuration
        let takeoff = clip.slice(JetpackJumpAnimation.takeoffFrames, frameDuration: frameDuration)
        let hover = clip.slice(JetpackJumpAnimation.hoverFrames, frameDuration: frameDuration)
        let land = clip.slice(JetpackJumpAnimation.landFrames, frameDuration: frameDuration)
        let hoverTime = max(
            JetpackJumpAnimation.hoverLoopDuration,
            Self.jetpackJumpDuration
                - JetpackJumpAnimation.takeoffDuration
                - JetpackJumpAnimation.landDuration
        )

        sprite.crossfadeOnce(
            to: takeoff,
            name: "jetpack-takeoff",
            duration: JetpackJumpAnimation.crossfadeDuration
        )
        sprite.run(
            .sequence([
                .wait(forDuration: JetpackJumpAnimation.takeoffDuration),
                .run { [weak sprite] in
                    sprite?.play(animation: hover, name: "jetpack-hover")
                },
                .wait(forDuration: hoverTime),
                .run { [weak sprite] in
                    sprite?.playOnce(animation: land, name: "jetpack-land")
                },
            ]),
            withKey: "jetpackPhases"
        )
    }

    /// Dissolves the landing pose into the facing idle clip.
    private func crossfadeJetpackToIdle() {
        guard let library = spriteLibrary,
              let sprite = renderer.playerAnimatedSprite() else { return }
        let idleName = playerFacing.animationName(locomotion: .idle)
        sprite.crossfade(
            name: idleName,
            library: library,
            duration: JetpackJumpAnimation.crossfadeDuration
        )
    }

    /// Drops world music under the hop so the jetpack cue stays audible.
    private func duckWorldMusicForJetpackJump() {
        let trackID = playerFx.trackID(for: "jetpack")
            ?? playerFx.trackID(for: "jump")
            ?? "pit-jump"
        Task { @MainActor in
            BackgroundMusicController.shared.duckForPhoneticCue(
                duration: max(
                    SoundEffectsController.shared.cueDuration(of: trackID),
                    Self.jetpackJumpDuration
                )
            )
        }
    }

    private func finishJetpackJump(
        gate: GridCoord,
        landing: GridCoord,
        completion: (() -> Void)?
    ) {
        renderer.playerAnimatedSprite()?.removeAction(forKey: "jetpackPhases")
        let gateNode = renderer.detachGateNode(at: gate, in: world)
        let openedCoords = world.openGate(at: gate)
        renderer.armRevealFade()
        world.setPlayerPosition(landing)
        renderer.render(world: world, focus: viewportFocus)
        renderer.setFloorNodesAlpha(0, at: openedCoords)
        movement.reset()
        crossfadeJetpackToIdle()
        captureContinueAndSave()
        revealGateEncounter(
            gateNode: gateNode,
            openedCoords: openedCoords,
            completion: completion
        )
    }
}
