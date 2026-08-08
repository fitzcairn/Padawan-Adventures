import SpriteKit

extension CombatDeflectScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        !didEnd
            && engine.outcome == nil
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
}
