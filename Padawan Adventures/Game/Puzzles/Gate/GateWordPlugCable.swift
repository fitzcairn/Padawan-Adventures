import SpriteKit
import UIKit

extension GateWordPlugScene {
    /// Springy tether between a token's home and the token itself.
    struct DragCable {
        let tokenID: UUID
        let container: SKNode
        let shade: SKShapeNode
        let segments: [SKSpriteNode]
        let arcGlow: SKShapeNode
        let arcBolt: SKShapeNode
        let arcCore: SKShapeNode
        var points: [CGPoint]
        var prevPoints: [CGPoint]
        var restLength: CGFloat
        var isPowered: Bool
    }

    static let cableLineWidth: CGFloat = 4
    static let cablePointCount = 12
    static let cableSegmentCount = 28
    static let cableSlack: CGFloat = 1.16
    static let cableGravity: CGFloat = 2_400
    static let cableConstraintIterations = 5
    static let cableArcRefreshInterval: TimeInterval = 0.055
    static let cableArcColor = UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
    static let cableArcCoreColor = UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)
    static let cableUnpoweredColor = UIColor(white: 0.22, alpha: 1)
    static let cablePoweredColor = UIColor(white: 0.78, alpha: 1)

    private static let braidTexture: SKTexture = makeBraidedCableTexture()

    func beginDragCable(for tokenID: UUID, powered: Bool = false) {
        tearDownCable(for: tokenID)
        guard let token = tokenNodes[tokenID], let home = tokenHome[tokenID] else { return }

        let start = home
        let end = cableEnd(for: token)
        let count = Self.cablePointCount
        let points: [CGPoint] = (0..<count).map { i in
            let t = CGFloat(i) / CGFloat(count - 1)
            return CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t
            )
        }
        let span = max(hypot(end.x - start.x, end.y - start.y), 1)
        let rest = (span * Self.cableSlack) / CGFloat(count - 1)

        let container = SKNode()
        container.name = "dragCable:\(tokenID.uuidString)"
        container.zPosition = 15

        let shade = SKShapeNode()
        shade.lineWidth = Self.cableLineWidth + 1.5
        shade.lineCap = .round
        shade.lineJoin = .round
        shade.strokeColor = UIColor(white: 0.05, alpha: 0.5)
        shade.fillColor = .clear
        shade.isUserInteractionEnabled = false
        container.addChild(shade)

        let segments: [SKSpriteNode] = (0..<Self.cableSegmentCount).map { _ in
            let sprite = SKSpriteNode(texture: Self.braidTexture)
            sprite.size = CGSize(width: Self.cableLineWidth * 1.6, height: Self.cableLineWidth)
            sprite.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            sprite.colorBlendFactor = 1
            sprite.isHidden = true
            sprite.isUserInteractionEnabled = false
            container.addChild(sprite)
            return sprite
        }

        let arcGlow = makeArcStroke(lineWidth: 5.5, color: Self.cableArcColor.withAlphaComponent(0.35))
        arcGlow.glowWidth = 4
        arcGlow.blendMode = .add
        let arcBolt = makeArcStroke(lineWidth: 1.6, color: Self.cableArcColor.withAlphaComponent(0.75))
        arcBolt.glowWidth = 1.5
        arcBolt.blendMode = .add
        let arcCore = makeArcStroke(lineWidth: 0.7, color: Self.cableArcCoreColor.withAlphaComponent(0.85))
        arcCore.blendMode = .add
        for arc in [arcGlow, arcBolt, arcCore] {
            arc.isHidden = true
            container.addChild(arc)
        }

        addChild(container)

        var cable = DragCable(
            tokenID: tokenID,
            container: container,
            shade: shade,
            segments: segments,
            arcGlow: arcGlow,
            arcBolt: arcBolt,
            arcCore: arcCore,
            points: points,
            prevPoints: points,
            restLength: rest,
            isPowered: powered
        )
        applyCableAppearance(&cable)
        applyCablePath(&cable)
        if powered {
            refreshCableArc(&cable)
        }
        tokenCables[tokenID] = cable
    }

    func energizeCable(for tokenID: UUID) {
        guard var cable = tokenCables[tokenID] else { return }
        cable.isPowered = true
        applyCableAppearance(&cable)
        refreshCableArc(&cable)
        tokenCables[tokenID] = cable
        syncArcLoop()
    }

    func updateDragCables(currentTime: TimeInterval) {
        guard !tokenCables.isEmpty else {
            cableLastUpdateTime = nil
            cableArcRefreshAccumulator = 0
            return
        }

        let dt: CGFloat
        if let last = cableLastUpdateTime {
            dt = min(1.0 / 30.0, max(1.0 / 120.0, CGFloat(currentTime - last)))
        } else {
            dt = 1.0 / 60.0
        }
        cableLastUpdateTime = currentTime
        cableArcRefreshAccumulator += TimeInterval(dt)

        let shouldRefreshArcs = cableArcRefreshAccumulator >= Self.cableArcRefreshInterval
        if shouldRefreshArcs {
            cableArcRefreshAccumulator = 0
        }

        for tokenID in Array(tokenCables.keys) {
            guard var cable = tokenCables[tokenID],
                  let token = tokenNodes[tokenID],
                  let home = tokenHome[tokenID]
            else {
                tearDownCable(for: tokenID)
                continue
            }

            let start = home
            let end = cableEnd(for: token)
            let span = max(hypot(end.x - start.x, end.y - start.y), 1)
            cable.restLength = (span * Self.cableSlack) / CGFloat(max(cable.points.count - 1, 1))

            cable.points[0] = start
            cable.points[cable.points.count - 1] = end
            cable.prevPoints[0] = start
            cable.prevPoints[cable.points.count - 1] = end

            // Verlet integration with gravity for a loose, springy hang.
            let g = Self.cableGravity * dt * dt
            for i in 1..<(cable.points.count - 1) {
                let p = cable.points[i]
                let prev = cable.prevPoints[i]
                let vx = (p.x - prev.x) * 0.98
                let vy = (p.y - prev.y) * 0.98
                cable.prevPoints[i] = p
                cable.points[i] = CGPoint(x: p.x + vx, y: p.y + vy - g)
            }

            for _ in 0..<Self.cableConstraintIterations {
                cable.points[0] = start
                cable.points[cable.points.count - 1] = end
                for i in 0..<(cable.points.count - 1) {
                    var a = cable.points[i]
                    var b = cable.points[i + 1]
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let dist = max(hypot(dx, dy), 0.0001)
                    let diff = (dist - cable.restLength) / dist
                    let offsetX = dx * 0.5 * diff
                    let offsetY = dy * 0.5 * diff
                    if i > 0 {
                        a.x += offsetX
                        a.y += offsetY
                        cable.points[i] = a
                    }
                    if i + 1 < cable.points.count - 1 {
                        b.x -= offsetX
                        b.y -= offsetY
                        cable.points[i + 1] = b
                    }
                }
            }

            applyCablePath(&cable)
            if cable.isPowered, shouldRefreshArcs {
                refreshCableArc(&cable)
            }
            tokenCables[tokenID] = cable
        }
    }

    func tearDownCable(for tokenID: UUID) {
        tokenCables[tokenID]?.container.removeFromParent()
        tokenCables[tokenID] = nil
        if tokenCables.isEmpty {
            cableLastUpdateTime = nil
            cableArcRefreshAccumulator = 0
        }
        syncArcLoop()
    }

    func tearDownAllCables() {
        for id in Array(tokenCables.keys) {
            tokenCables[id]?.container.removeFromParent()
            tokenCables[id] = nil
        }
        cableLastUpdateTime = nil
        cableArcRefreshAccumulator = 0
        syncArcLoop()
    }

    /// Recreate settled cables for already-plugged letters after a layout rebuild.
    func restorePluggedCables() {
        for letterID in engine.plugged.values {
            beginDragCable(for: letterID, powered: true)
        }
    }

    private func cableEnd(for token: SKNode) -> CGPoint {
        CGPoint(x: token.position.x, y: token.position.y - laidOutDiameter * 0.5)
    }

    private func makeArcStroke(lineWidth: CGFloat, color: UIColor) -> SKShapeNode {
        let node = SKShapeNode()
        node.lineWidth = lineWidth
        node.lineCap = .round
        node.lineJoin = .round
        node.strokeColor = color
        node.fillColor = .clear
        node.isUserInteractionEnabled = false
        return node
    }

    private func applyCableAppearance(_ cable: inout DragCable) {
        let color = cable.isPowered ? Self.cablePoweredColor : Self.cableUnpoweredColor
        for segment in cable.segments {
            segment.color = color
            segment.colorBlendFactor = 1
        }
    }

    private func applyCablePath(_ cable: inout DragCable) {
        let samples = resampleCable(points: cable.points, count: cable.segments.count + 1)

        let shadePath = CGMutablePath()
        if let first = samples.first {
            shadePath.move(to: first)
            for point in samples.dropFirst() {
                shadePath.addLine(to: point)
            }
        }
        cable.shade.path = shadePath

        for i in 0..<cable.segments.count {
            let a = samples[i]
            let b = samples[i + 1]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len = hypot(dx, dy)
            let segment = cable.segments[i]
            guard len > 0.25 else {
                segment.isHidden = true
                continue
            }
            segment.isHidden = false
            segment.position = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
            segment.zRotation = atan2(dy, dx)
            segment.size = CGSize(width: max(len + 0.5, Self.cableLineWidth), height: Self.cableLineWidth)
        }

        if !cable.isPowered {
            cable.arcGlow.isHidden = true
            cable.arcBolt.isHidden = true
            cable.arcCore.isHidden = true
        }
    }

    private func refreshCableArc(_ cable: inout DragCable) {
        let samples = resampleCable(points: cable.points, count: 10)
        guard samples.count >= 2 else {
            cable.arcGlow.isHidden = true
            cable.arcBolt.isHidden = true
            cable.arcCore.isHidden = true
            return
        }

        let path = makeSubtleArcPath(along: samples, using: &cableArcRNG)
        cable.arcGlow.path = path
        cable.arcBolt.path = path
        cable.arcCore.path = path
        cable.arcGlow.isHidden = false
        cable.arcBolt.isHidden = false
        cable.arcCore.isHidden = false

        // Soft flicker so the current feels alive without overpowering the braid.
        cable.arcGlow.alpha = CGFloat.random(in: 0.18...0.38, using: &cableArcRNG)
        cable.arcBolt.alpha = CGFloat.random(in: 0.35...0.65, using: &cableArcRNG)
        cable.arcCore.alpha = CGFloat.random(in: 0.40...0.80, using: &cableArcRNG)
    }

    /// Gentle jagged arc hugging the cable centerline with small lateral jitter.
    private func makeSubtleArcPath(
        along samples: [CGPoint],
        using rng: inout some RandomNumberGenerator
    ) -> CGPath {
        let path = CGMutablePath()
        guard let first = samples.first, let last = samples.last else { return path }
        path.move(to: first)
        guard samples.count > 2 else {
            path.addLine(to: last)
            return path
        }

        for i in 1..<(samples.count - 1) {
            let prev = samples[i - 1]
            let point = samples[i]
            let next = samples[i + 1]
            let dx = next.x - prev.x
            let dy = next.y - prev.y
            let len = max(hypot(dx, dy), 0.001)
            let px = -dy / len
            let py = dx / len
            let t = CGFloat(i) / CGFloat(samples.count - 1)
            let taper = sin(t * .pi)
            let offset = CGFloat.random(in: -2.2...2.2, using: &rng) * taper
            path.addLine(to: CGPoint(x: point.x + px * offset, y: point.y + py * offset))
        }
        path.addLine(to: last)
        return path
    }

    private func resampleCable(points: [CGPoint], count: Int) -> [CGPoint] {
        guard count > 1, points.count >= 2 else {
            return Array(repeating: points.first ?? .zero, count: max(count, 0))
        }
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        let total = lengths.last ?? 0
        // Collapsed cable (all points stacked) — avoid walking idx past the array.
        guard total > 0.0001 else {
            return Array(repeating: points[0], count: count)
        }
        let last = points.count - 1
        return (0..<count).map { i in
            if i == count - 1 { return points[last] }
            let target = total * CGFloat(i) / CGFloat(count - 1)
            var idx = 1
            while idx < last, lengths[idx] < target { idx += 1 }
            let i1 = idx
            let i0 = i1 - 1
            let seg = max(lengths[i1] - lengths[i0], 0.0001)
            let t = (target - lengths[i0]) / seg
            let a = points[i0]
            let b = points[i1]
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    private static func makeBraidedCableTexture() -> SKTexture {
        let size = CGSize(width: 16, height: 16)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        // Neutral greyscale braid — tinted dark/light grey via colorBlendFactor.
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            UIColor(white: 0.45, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            cg.setLineCap(.square)
            cg.setLineWidth(1.25)

            // Light strand \
            UIColor(white: 0.78, alpha: 1).setStroke()
            cg.beginPath()
            for i in -3...5 {
                let x = CGFloat(i) * 4
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x + size.height, y: size.height))
            }
            cg.strokePath()

            // Dark strand /
            UIColor(white: 0.18, alpha: 1).setStroke()
            cg.beginPath()
            for i in -3...5 {
                let x = CGFloat(i) * 4
                cg.move(to: CGPoint(x: x, y: size.height))
                cg.addLine(to: CGPoint(x: x + size.height, y: 0))
            }
            cg.strokePath()

            // Mid highlight strands for braid volume
            UIColor(white: 0.62, alpha: 0.85).setStroke()
            cg.setLineWidth(0.7)
            cg.beginPath()
            for i in -3...5 {
                let x = CGFloat(i) * 4 + 2
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x + size.height, y: size.height))
            }
            cg.strokePath()
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        return texture
    }
}
