import SpriteKit

extension GateWordPlugScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && !inputLocked
            && dragTokenID == nil
            && !tokenNodes.isEmpty
    }

    var demoMoves: [MinigameDemoMove] {
        guard let slot = engine.slots.first(where: { !engine.isSlotFilled($0.id) }),
              let socket = socketNodes[slot.id] else {
            return []
        }
        let answer = slot.letter
        return engine.tray.compactMap { token in
            guard !engine.isTokenPlugged(token.id),
                  let node = tokenNodes[token.id] else { return nil }
            return MinigameDemoMove(
                gesture: .drag(from: node.position, to: socket.position),
                isCorrect: token.letter == answer,
                coinAnchor: socket.position
            )
        }
    }

    var demoCoinAnchor: CGPoint? {
        guard let slot = engine.slots.last(where: { engine.isSlotFilled($0.id) }) else {
            return nil
        }
        return socketNodes[slot.id]?.position
    }

    var demoIsFinished: Bool { didEnd }
}
