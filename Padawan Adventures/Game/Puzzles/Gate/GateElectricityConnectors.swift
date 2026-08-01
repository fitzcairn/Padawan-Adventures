import SpriteKit
import UIKit

extension GateScene {
    /// One light-blue electricity span between two linked capacitors.
    struct ElectricConnector {
        var start: CGPoint
        var end: CGPoint
        let container: SKNode
        let baseline: SKShapeNode
        let glow: SKShapeNode
        let bolt: SKShapeNode
        let core: SKShapeNode
        let branch: SKShapeNode
        let boltVariants: [CGPath]
        let branchVariants: [CGPath]
    }

    /// Test seam: pre-baked path counts per connector, to prove geometry is not
    /// regenerated per frame.
    var electricityVariantCounts: [(bolt: Int, branch: Int)] {
        connectorSegments.map { ($0.boltVariants.count, $0.branchVariants.count) }
    }
    /// Test seam: builds one connector with pre-baked bolt/branch variants.
    func addConnectorLineForTesting(from start: CGPoint, to end: CGPoint) {
        addConnectorLine(from: start, to: end)
    }

    /// Test seam: force one electricity refresh cycle.
    func refreshElectricityConnectorsForTesting() {
        electricityRefreshAccumulator = Self.electricityRefreshInterval
        refreshElectricityConnectors(dt: 0)
    }

    func addConnectorLine(from start: CGPoint, to end: CGPoint) {
        let container = SKNode()
        container.name = "connector"
        container.zPosition = 5

        let baseline = makeGlowStroke(
            lineWidth: 4,
            color: connectorColor.withAlphaComponent(0.35),
            glowWidth: 0
        )
        let glow = makeGlowStroke(
            lineWidth: 10,
            color: connectorColor.withAlphaComponent(0.45),
            glowWidth: 6
        )
        let bolt = makeGlowStroke(
            lineWidth: 4.5,
            color: connectorColor,
            glowWidth: 2
        )
        let core = makeGlowStroke(
            lineWidth: 1.8,
            color: connectorCoreColor,
            glowWidth: 0
        )
        let branch = makeGlowStroke(
            lineWidth: 2.2,
            color: connectorColor.withAlphaComponent(0.9),
            glowWidth: 1
        )
        glow.blendMode = .add
        bolt.blendMode = .add
        core.blendMode = .add
        branch.blendMode = .add

        container.addChild(baseline)
        container.addChild(glow)
        container.addChild(bolt)
        container.addChild(core)
        container.addChild(branch)
        addChild(container)

        let straight = CGMutablePath()
        straight.move(to: start)
        straight.addLine(to: end)
        baseline.path = straight

        let boltVariants = (0..<6).map { _ in
            makeElectricityPath(from: start, to: end, using: &electricityRNG)
        }
        let branchVariants = (0..<4).compactMap { _ in
            makeElectricityBranchPath(from: start, to: end, using: &electricityRNG)
        }

        var connector = ElectricConnector(
            start: start,
            end: end,
            container: container,
            baseline: baseline,
            glow: glow,
            bolt: bolt,
            core: core,
            branch: branch,
            boltVariants: boltVariants,
            branchVariants: branchVariants
        )
        applyElectricityPaths(to: &connector)
        connectorSegments.append(connector)
    }

    func clearConnectorSegments() {
        for segment in connectorSegments {
            segment.container.removeFromParent()
        }
        connectorSegments.removeAll(keepingCapacity: true)
        electricityRefreshAccumulator = 0
    }

    /// Flicker / re-jag active connectors so the spans read as arcing electricity.
    func refreshElectricityConnectors(dt: TimeInterval) {
        guard !connectorSegments.isEmpty else { return }
        electricityRefreshAccumulator += dt
        guard electricityRefreshAccumulator >= Self.electricityRefreshInterval else { return }
        electricityRefreshAccumulator = 0
        for index in connectorSegments.indices {
            applyElectricityPaths(to: &connectorSegments[index])
        }
    }

    func applyElectricityPaths(to connector: inout ElectricConnector) {
        if let boltPath = connector.boltVariants.randomElement(using: &electricityRNG) {
            connector.glow.path = boltPath
            connector.bolt.path = boltPath
            connector.core.path = boltPath
        }

        // Brightness flicker — keeps the arc feeling alive between re-jags.
        let boltAlpha = CGFloat.random(in: 0.72...1.0, using: &electricityRNG)
        let coreAlpha = CGFloat.random(in: 0.55...1.0, using: &electricityRNG)
        connector.bolt.alpha = boltAlpha
        connector.core.alpha = coreAlpha
        connector.glow.alpha = CGFloat.random(in: 0.35...0.7, using: &electricityRNG)

        // Occasional short side-arc branching off the main span.
        if CGFloat.random(in: 0...1, using: &electricityRNG) < 0.32,
           let branchPath = connector.branchVariants.randomElement(using: &electricityRNG) {
            connector.branch.path = branchPath
            connector.branch.alpha = CGFloat.random(in: 0.35...0.85, using: &electricityRNG)
            connector.branch.isHidden = false
        } else {
            connector.branch.path = nil
            connector.branch.isHidden = true
        }
    }

    /// Jagged polyline along `start`→`end`, with displacement tapered at both endpoints.
    func makeElectricityPath(
        from start: CGPoint,
        to end: CGPoint,
        using rng: inout some RandomNumberGenerator
    ) -> CGPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        let path = CGMutablePath()
        path.move(to: start)
        guard length > 2 else {
            path.addLine(to: end)
            return path
        }

        // Unit perpendicular for lateral bolt displacement.
        let px = -dy / length
        let py = dx / length

        let jagCount = max(Int(length / 16), 3)
        let maxOffset = min(length * 0.14, 14)

        for step in 1..<jagCount {
            let t = CGFloat(step) / CGFloat(jagCount)
            // Soft envelope so the bolt stays anchored at the capacitors.
            let taper = sin(t * .pi)
            let offset = CGFloat.random(in: -maxOffset...maxOffset, using: &rng) * taper
            // Slight uneven progress along the span (not perfectly even segments).
            let alongJitter = CGFloat.random(in: -0.04...0.04, using: &rng) * (1 - abs(t - 0.5) * 2)
            let along = min(max(t + alongJitter, 0.02), 0.98)
            path.addLine(to: CGPoint(
                x: start.x + dx * along + px * offset,
                y: start.y + dy * along + py * offset
            ))
        }
        path.addLine(to: end)
        return path
    }

    /// Short fork that peels off the main span, then dies out — reads as a secondary arc.
    func makeElectricityBranchPath(
        from start: CGPoint,
        to end: CGPoint,
        using rng: inout some RandomNumberGenerator
    ) -> CGPath? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 28 else { return nil }

        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        let branchStartT = CGFloat.random(in: 0.25...0.7, using: &rng)
        let origin = CGPoint(
            x: start.x + dx * branchStartT,
            y: start.y + dy * branchStartT
        )
        let branchLength = length * CGFloat.random(in: 0.18...0.38, using: &rng)
        let side: CGFloat = Bool.random(using: &rng) ? 1 : -1
        let tip = CGPoint(
            x: origin.x + ux * branchLength * CGFloat.random(in: 0.35...0.8, using: &rng)
                + px * side * branchLength * CGFloat.random(in: 0.45...0.95, using: &rng),
            y: origin.y + uy * branchLength * CGFloat.random(in: 0.35...0.8, using: &rng)
                + py * side * branchLength * CGFloat.random(in: 0.45...0.95, using: &rng)
        )
        return makeElectricityPath(from: origin, to: tip, using: &rng)
    }
}
