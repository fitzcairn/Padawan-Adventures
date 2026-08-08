import SpriteKit

extension CombatScene: MinigameDemoStage {
    var demoAcceptsInput: Bool {
        engine.acceptsInput && shotVisuals.contains { $0.value.role == .inbound }
    }

    var demoMoves: [MinigameDemoMove] {
        shotVisuals.compactMap { _, visual in
            guard visual.role == .inbound else { return nil }
            let bounds = shotSpriteBounds(for: visual.node)
            // Short stroke that crosses the sprite so resolveSlashHits registers a hit.
            let midY = bounds.midY
            let points = [
                CGPoint(x: bounds.minX - 8, y: midY - 6),
                CGPoint(x: bounds.midX, y: midY + 6),
                CGPoint(x: bounds.maxX + 8, y: midY - 4),
            ]
            return MinigameDemoMove(
                gesture: .swipe(points),
                isCorrect: visual.isTarget,
                coinAnchor: visual.node.position
            )
        }
    }

    var demoCoinAnchor: CGPoint? {
        shotVisuals.values.first { $0.role == .inbound && $0.isTarget }?.node.position
            ?? enemyNode?.position
    }

    var demoIsFinished: Bool { didEnd }
}
