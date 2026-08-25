import SpriteKit

extension GameScene {
    static let jetpackJumpDuration: TimeInterval = 0.7

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
        let facingLeft = end.x < start.x
        playerFacing = facingLeft ? .left : .right
        if let sprite = renderer.playerAnimatedSprite(), let library = spriteLibrary {
            sprite.play(name: facingLeft ? "jump_left" : "jump_right", library: library)
        }
        SoundEffectsController.shared.play(event: "jump", from: playerFx)

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

    private func finishJetpackJump(
        gate: GridCoord,
        landing: GridCoord,
        completion: (() -> Void)?
    ) {
        let gateNode = renderer.detachGateNode(at: gate, in: world)
        let openedCoords = world.openGate(at: gate)
        renderer.armRevealFade()
        world.setPlayerPosition(landing)
        renderer.render(world: world, focus: viewportFocus)
        renderer.setFloorNodesAlpha(0, at: openedCoords)
        resumeWorldPlayerIdle()
        captureContinueAndSave()
        revealGateEncounter(
            gateNode: gateNode,
            openedCoords: openedCoords,
            completion: completion
        )
    }
}
