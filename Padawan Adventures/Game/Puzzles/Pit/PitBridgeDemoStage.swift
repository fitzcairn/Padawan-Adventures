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

    /// Replays the opening word cue suppressed during the tutorial lead-in.
    func demoResumeGameplayAudio() {
        replayWordSound()
    }
}
