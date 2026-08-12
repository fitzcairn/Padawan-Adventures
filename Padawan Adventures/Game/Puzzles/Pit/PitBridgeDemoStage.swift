import SpriteKit

extension PitBridgeScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && !isJumping
            && didRevealTrayForRound
            && isUserInteractionEnabled
            && draggedNode == nil
            && !trayNodes.isEmpty
    }

    var demoMoves: [MinigameDemoMove] {
        let slot = geometry.slotCenter(engine.roundIndex)
        return engine.choices.compactMap { choice in
            guard let node = trayNodes[choice.id] else { return nil }
            return MinigameDemoMove(
                gesture: .drag(from: node.position, to: slot),
                isCorrect: choice.isCorrect,
                coinAnchor: slot
            )
        }
    }

    var demoCoinAnchor: CGPoint? {
        geometry.slotCenter(max(engine.roundIndex - 1, 0))
    }

    var demoIsFinished: Bool { didEnd }

    var demoScript: MinigameDemoScript? { PitBridgeDemoScript(stage: self) }

    /// Replays the opening word cue suppressed during the tutorial lead-in.
    func demoResumeGameplayAudio() {
        replayWordSound()
    }
}

extension PitBridgeScene: PitBridgeDemoStaging {
    var demoIsReady: Bool { demoAcceptsInput }
    var demoIsOver: Bool { demoIsFinished }
    var demoWrongMove: MinigameDemoMove? { demoMoves.first { !$0.isCorrect } }
    var demoCorrectMove: MinigameDemoMove? { demoMoves.first { $0.isCorrect } }

    func demoRestart() {
        removeAction(forKey: Self.promptWatchdogKey)
        removeAction(forKey: Self.promptSoundKey)
        removeAction(forKey: Self.letterCueActionKey)
        removeAction(forKey: Self.winSoundActionKey)
        playerNode?.removeAllActions()
        draggedNode?.removeAllActions()
        draggedNode = nil
        dragMoved = false
        didEnd = false
        isJumping = false
        didRevealTrayForRound = false
        promptContinuationArmed = false
        isUserInteractionEnabled = true
        // `buildArena()` calls `removeAllChildren()` — keep the tutorial cursor/coins.
        preservingDemoOverlays {
            engine.begin()
            buildArena()
        }
        beginRound()
    }
}
