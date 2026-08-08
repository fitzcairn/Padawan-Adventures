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
        return letterNodes.compactMap { id, node in
            // Skip already-matched letters — tapping them is a no-op / wrong path.
            guard !engine.matchedIDs.contains(id) else { return nil }
            return MinigameDemoMove(
                gesture: .tap(node.position),
                isCorrect: id == target,
                coinAnchor: switchNodes[id]?.position ?? node.position
            )
        }
    }

    var demoCoinAnchor: CGPoint? {
        for letter in engine.letters.reversed() where engine.matchedIDs.contains(letter.id) {
            return switchNodes[letter.id]?.position ?? letterNodes[letter.id]?.position
        }
        return nil
    }

    var demoIsFinished: Bool { didEnd }
}
