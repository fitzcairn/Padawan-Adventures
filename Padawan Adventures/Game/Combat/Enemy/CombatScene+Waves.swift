import SpriteKit

extension CombatScene {
    // MARK: - Cleared

    func resolveWaveCleared(clearedShotID: UUID) {
        if let visual = shotVisuals[clearedShotID] {
            let position = visual.node.position
            removeShotNode(id: clearedShotID)
            playExplosion(at: position) // Keeps the slash_hit sound for the correct cut.
        }
        let remaining = Array(shotVisuals.keys)
        resolvingSpriteCount = remaining.count
        for id in remaining { sweepOffScreen(shotID: id) }
        if resolvingSpriteCount == 0 { completeWaveResolution() }
    }

    /// Accelerates a decoy out through the nearest side of the arena.
    func sweepOffScreen(shotID: UUID) {
        guard var visual = shotVisuals[shotID] else { return }
        let current = visual.node.position
        let exitX: CGFloat = current.x < size.width * 0.5
            ? -size.width * 0.25
            : size.width * 1.25
        let exit = CGPoint(
            x: exitX,
            y: min(current.y + size.height * 0.15, size.height * 1.1)
        )
        retarget(&visual, from: current, to: exit, duration: Self.sweepOffSeconds, role: .sweepingOff)
        shotVisuals[shotID] = visual
        visual.node.run(.fadeOut(withDuration: Self.sweepOffSeconds))
    }

    // MARK: - Failed

    func resolveWaveFailed(reason: CombatWaveFailure) {
        didPlayWaveDamageSound = false
        var charging = Array(shotVisuals.keys)

        switch reason {
        case let .wrongSlash(id):
            playSlashErrorSound()
            if let visual = shotVisuals[id] {
                flashRedAndFade(visual.node)
                shotVisuals[id] = nil // The action removes the node itself.
            }
            charging.removeAll { $0 == id }
        case let .impact(id):
            charging.removeAll { $0 == id }
            // Already touching the player: explode and take the damage now.
            landSprite(shotID: id)
        }

        resolvingSpriteCount = charging.count
        for id in charging { chargePlayer(shotID: id) }
        if resolvingSpriteCount == 0 { completeWaveResolution() }
    }

    /// Accelerates a sprite from wherever it is straight into the player.
    func chargePlayer(shotID: UUID) {
        guard var visual = shotVisuals[shotID], let playerNode else { return }
        let current = visual.node.position
        let target = bodyCenter(of: playerNode, height: playerSpriteHeight)
        let distance = Double(hypot(target.x - current.x, target.y - current.y))
        let scaled = distance / Double(max(size.height, 1)) * Self.chargeReferenceSeconds
        let duration = min(
            max(scaled, Self.chargeSecondsRange.lowerBound),
            Self.chargeSecondsRange.upperBound
        )
        retarget(&visual, from: current, to: target, duration: duration, role: .charging)
        shotVisuals[shotID] = visual
    }

    /// A sprite reaching the player on a failed wave: explosion where it hits, with the
    /// damage sound, player flash, and impact burst fired only for the first one.
    func landSprite(shotID: UUID) {
        guard let visual = shotVisuals[shotID] else { return }
        let position = visual.node.position
        removeShotNode(id: shotID)
        explosionVisual(at: position)
        guard !didPlayWaveDamageSound else { return }
        didPlayWaveDamageSound = true
        SoundEffectsController.shared.play(event: "damage", from: playerFx)
        flashPlayer(color: .orange)
        impactBurstVisual(at: position)
    }

    // MARK: - Bookkeeping

    func noteResolutionStepFinished() {
        resolvingSpriteCount = max(0, resolvingSpriteCount - 1)
        if resolvingSpriteCount == 0 { completeWaveResolution() }
    }

    func completeWaveResolution() {
        for event in engine.finishWaveResolution() { handle(event) }
    }

    /// Nearly straight re-aim: control points sit on the line so the move reads as a lunge.
    private func retarget(
        _ visual: inout ShotVisual,
        from current: CGPoint,
        to destination: CGPoint,
        duration: Double,
        role: ShotRole
    ) {
        visual.pathStart = current
        visual.pathEnd = destination
        visual.pathControl1 = CGPoint(
            x: current.x + (destination.x - current.x) * 0.33,
            y: current.y + (destination.y - current.y) * 0.33
        )
        visual.pathControl2 = CGPoint(
            x: current.x + (destination.x - current.x) * 0.66,
            y: current.y + (destination.y - current.y) * 0.66
        )
        visual.pathStartedAt = sceneElapsed
        visual.pathDurationSeconds = duration
        visual.role = role
        visual.node.position = current
    }
}
