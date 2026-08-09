import SpriteKit

extension CombatScene: MinigameDemoStage {
    /// Vertical band around the scene midpoint where the tutorial demonstrates swipes.
    /// Letters spawn at the top; waiting until they enter this band keeps the hand
    /// centered instead of swiping up near the enemy.
    private var demoSwipeMidY: CGFloat { size.height * 0.5 }
    private var demoSwipeBandHalfHeight: CGFloat { size.height * 0.12 }

    var demoAcceptsInput: Bool {
        engine.acceptsInput && shotVisuals.contains { _, visual in
            visual.role == .inbound && isInDemoSwipeBand(shotSpriteBounds(for: visual.node))
        }
    }

    var demoMoves: [MinigameDemoMove] {
        shotVisuals.compactMap { _, visual in
            guard visual.role == .inbound else { return nil }
            let bounds = shotSpriteBounds(for: visual.node)
            guard isInDemoSwipeBand(bounds) else { return nil }
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
                coinAnchor: demoCoinSpawnPoint
            )
        }
    }

    /// Centre of the scene so the won-coin pop reads clearly before the corner arc.
    var demoCoinAnchor: CGPoint? { demoCoinSpawnPoint }

    private var demoCoinSpawnPoint: CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    }

    var demoIsFinished: Bool { didEnd }

    private func isInDemoSwipeBand(_ bounds: CGRect) -> Bool {
        abs(bounds.midY - demoSwipeMidY) <= demoSwipeBandHalfHeight
    }
}
