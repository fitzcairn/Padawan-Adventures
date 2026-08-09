import SpriteKit

extension PitSoundOutWordScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && !isJumping
            && !isDraggingPlayer
            && isUserInteractionEnabled
            && engine.currentIndex != nil
            && !candidateNodes.isEmpty
    }

    var demoMoves: [MinigameDemoMove] {
        guard let playerNode, let answer = engine.currentGrapheme else { return [] }
        let origin = playerNode.position
        return candidateNodes.compactMap { node in
            guard let grapheme = node.userData?["grapheme"] as? String else { return nil }
            return MinigameDemoMove(
                gesture: .drag(from: origin, to: node.position),
                isCorrect: grapheme == answer,
                coinAnchor: node.position
            )
        }
    }

    var demoCoinAnchor: CGPoint? { landedTileNodes.last?.position }

    var demoIsFinished: Bool { didEnd || engine.isSolved }

    /// Replays the opening word cue suppressed during the tutorial lead-in.
    func demoResumeGameplayAudio() {
        replayWordSound()
    }
}
