import SpriteKit

extension GateGraphemeMatchScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && !inputLocked
            && !letterNodes.isEmpty
            && engine.currentTargetID != nil
    }

    var demoMoves: [MinigameDemoMove] {
        let target = engine.currentTargetID
        // Spawn at screen centre — switch nodes are children of each letter, so their
        // local positions sit near the origin and would place coins off-screen.
        let coinSpawn = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        return letterNodes.compactMap { id, node in
            // Skip already-matched letters — tapping them is a no-op / wrong path.
            guard !engine.matchedIDs.contains(id) else { return nil }
            return MinigameDemoMove(
                gesture: .tap(node.position),
                isCorrect: id == target,
                coinAnchor: coinSpawn
            )
        }
    }

    var demoCoinAnchor: CGPoint? {
        CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    }

    var demoIsFinished: Bool { didEnd }
}
