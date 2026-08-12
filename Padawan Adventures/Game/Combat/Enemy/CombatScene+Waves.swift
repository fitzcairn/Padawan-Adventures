import SpriteKit

extension CombatScene {
    // MARK: - Cleared

    func resolveWaveCleared(clearedShotID: UUID) {
        let remaining = Array(shotVisuals.keys).filter { $0 != clearedShotID }
        resolvingSpriteCount = remaining.count + (shotVisuals[clearedShotID] != nil ? 1 : 0)
        reflectToEnemy(shotID: clearedShotID)
        for id in remaining { sweepOffScreen(shotID: id) }
        if resolvingSpriteCount == 0 { completeWaveResolution() }
    }

    /// Accelerates the slashed target back at the enemy on a curved return arc.
    func reflectToEnemy(shotID: UUID) {
        guard var visual = shotVisuals[shotID], let enemyNode else {
            noteResolutionStepFinished()
            return
        }
        let current = visual.node.position
        let destination = bodyCenter(of: enemyNode, height: enemySpriteHeight)
        let progress = Double(pathProgress(for: visual))
        let remaining = max(visual.pathDurationSeconds * (1 - progress), 0.05)
        let duration = min(
            max(remaining / Self.returnSpeedMultiplier, Self.returnSecondsRange.lowerBound),
            Self.returnSecondsRange.upperBound
        )
        // Bend sideways so the return reads as a ricochet rather than a straight rewind.
        let mid = CGPoint(
            x: (current.x + destination.x) * 0.5,
            y: (current.y + destination.y) * 0.5
        )
        let lateral: CGFloat = abs(current.x - size.width * 0.5) < size.width * 0.05
            ? (Bool.random() ? 1 : -1)
            : (current.x < size.width * 0.5 ? -1 : 1)
        let bend = size.width * 0.22 * lateral
        visual.pathStart = current
        visual.pathEnd = destination
        visual.pathControl1 = CGPoint(
            x: current.x + (mid.x - current.x) * 0.55 + bend * 0.65,
            y: current.y + (destination.y - current.y) * 0.25
        )
        visual.pathControl2 = CGPoint(
            x: mid.x + bend,
            y: mid.y + (destination.y - mid.y) * 0.35
        )
        visual.pathStartedAt = sceneElapsed
        visual.pathDurationSeconds = duration
        visual.role = .returning
        visual.node.position = current
        shotVisuals[shotID] = visual
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

    // MARK: - Wrong slash (soft miss)

    /// Stops the decoy in place, then flashes / fades it with an explosion. Other inbound
    /// letters keep flying so the player can still slash the cued target.
    func discardWrongShot(shotID: UUID) {
        playSlashErrorSound()
        guard let visual = shotVisuals[shotID] else { return }
        let node = visual.node
        let position = node.position
        shotVisuals[shotID] = nil
        flashRedFadeAndExplode(node, at: position)
    }

    // MARK: - Failed

    func resolveWaveFailed(reason: CombatWaveFailure) {
        didPlayWaveDamageSound = false
        var charging = Array(shotVisuals.keys)

        switch reason {
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

    /// Correct letter reaching the enemy: explosion (with enemy_damage) on the monster.
    func landReturnOnEnemy(shotID: UUID) {
        guard let visual = shotVisuals[shotID] else { return }
        let position = visual.node.position
        removeShotNode(id: shotID)
        playExplosion(at: position)
        animateMonsterHPBar()
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
