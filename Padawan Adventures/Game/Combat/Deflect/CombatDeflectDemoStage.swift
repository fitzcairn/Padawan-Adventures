import SpriteKit

extension CombatDeflectScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && engine.outcome == nil
            && !isWrongLetterFeedbackActive
            && (engine.activeOrb.map { !$0.isResolved } ?? false)
    }

    var demoMoves: [MinigameDemoMove] {
        let answer = engine.activeOrb?.ring
        return engine.rings.map { ring in
            let point = geometry.ringCenter(ring)
            return MinigameDemoMove(
                gesture: .tap(point),
                isCorrect: ring == answer,
                coinAnchor: enemyNode.map { bodyCenter(of: $0, height: enemySpriteHeight) }
                    ?? point
            )
        }
    }

    var demoCoinAnchor: CGPoint? {
        enemyNode.map { bodyCenter(of: $0, height: enemySpriteHeight) }
    }

    var demoIsFinished: Bool { didEnd }

    /// Restarts combat begin SFX suppressed during the tutorial lead-in.
    func demoResumeGameplayAudio() {
        stopCombatLoop()
        SoundEffectsController.shared.play(event: "combat_start", from: playerFx)
        activeLoopTrackID = SoundEffectsController.shared.startLoop(
            event: "combat_loop",
            from: playerFx
        )
    }

    var demoDemonstratesPrelude: Bool { true }

    /// Tap the orb itself so the player sees that a tap on the projectile replays the
    /// word. Only offered while the orb is clear of the rings — inside the cluster the
    /// ring branch of `touchesBegan` would take the tap and deflect instead.
    var demoPreludeMoves: [MinigameDemoMove] {
        guard !didEnd,
              engine.outcome == nil,
              let orb = activeOrb,
              engine.activeOrb?.isResolved == false else { return [] }
        let point = predictedOrbCenter(of: orb, after: MinigameDemoPointer.approachSeconds)
        guard geometry.hitTest(point) == nil else { return [] }
        return [MinigameDemoMove(gesture: .tap(point), isCorrect: false)]
    }
}
