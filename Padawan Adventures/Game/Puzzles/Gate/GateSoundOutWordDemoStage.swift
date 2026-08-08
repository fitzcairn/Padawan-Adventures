import SpriteKit

extension GateSoundOutWordScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && !inputLocked
            && !isCompletingWin
            && dragChoiceID == nil
            && !choiceNodes.isEmpty
    }

    var demoMoves: [MinigameDemoMove] {
        let playCenter = CGPoint(x: playAreaRect.midX, y: playAreaRect.midY)
        let drop = nearestValidDropPoint(to: playCenter) ?? playCenter
        guard isValidDrop(drop) else { return [] }
        let answer = engine.currentGrapheme
        return engine.currentChoices.compactMap { choice in
            guard let node = choiceNodes[choice.id] else { return nil }
            return MinigameDemoMove(
                gesture: .drag(from: node.position, to: drop),
                isCorrect: choice.grapheme == answer,
                coinAnchor: drop
            )
        }
    }

    var demoCoinAnchor: CGPoint? { placedNodes.last?.position }

    var demoIsFinished: Bool { didEnd || isCompletingWin }
}
