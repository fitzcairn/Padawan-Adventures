import SpriteKit

@MainActor
final class MinigameDemoCoinLayer {
    static let rootName = "demoCoinLayer"

    private let root = SKNode()
    private var coins: [SKSpriteNode] = []
    private let side: CGFloat
    private weak var scene: SKScene?
    /// Single-coin flights performed via `flyCoinToCorner`. Tests assert this without
    /// racing the animation.
    private(set) var flightCount = 0

    init(scene: SKScene, side: CGFloat = 44) {
        self.scene = scene
        self.side = side
        root.name = Self.rootName
        root.zPosition = MinigameDemoCursor.zPosition - 100
        scene.addChild(root)
    }

    var count: Int { coins.count }

    func dropCoin(at point: CGPoint) {
        let node = makeCoinNode(at: point)
        // Visible immediately — fade/scale are polish. If the scene's action loop is
        // briefly stalled, a fully transparent coin would never appear.
        node.alpha = 1
        node.setScale(1)
        root.addChild(node)
        coins.append(node)

        node.setScale(0.1)
        node.run(.sequence([
            .scale(to: 1.15, duration: 0.18),
            .scale(to: 1.0, duration: 0.10),
        ]), withKey: "pop")
        node.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 6, duration: 0.6),
            .moveBy(x: 0, y: -6, duration: 0.6),
        ])), withKey: "bob")
    }

    /// Pops a coin in at `point`, then arcs it to the scene's bottom-left corner while
    /// shrinking to nothing — the SpriteKit twin of `MinigameResultOverlay`'s
    /// `CoinArcFlight`. Removes the coin when it lands.
    func flyCoinToCorner(
        from point: CGPoint,
        holdSeconds: TimeInterval = 0.35,
        flightSeconds: TimeInterval = 0.75
    ) async {
        guard let scene else { return }
        let node = makeCoinNode(at: point)
        node.alpha = 1
        node.setScale(0.1)
        root.addChild(node)
        flightCount += 1

        // Prefer `run(_:withKey:)` — the async `run(_:)` overload hangs when the scene
        // has no update loop (unit tests use a bare SKScene).
        node.run(.sequence([
            .scale(to: 1.15, duration: 0.18),
            .scale(to: 1.0, duration: 0.10),
        ]), withKey: "pop")
        try? await Task.sleep(nanoseconds: UInt64(max(0, holdSeconds) * 1_000_000_000))

        let end = CGPoint.zero
        let control = CGPoint(
            x: point.x + (end.x - point.x) * 0.75,
            y: max(point.y, end.y) + scene.size.height * 0.22
        )
        let span = max(flightSeconds, 0.01)
        let flight = SKAction.customAction(withDuration: span) { node, elapsed in
            let raw = min(max(CGFloat(elapsed) / CGFloat(span), 0), 1)
            // Smoothstep stands in for SwiftUI's easeInOut.
            let t = raw * raw * (3 - 2 * raw)
            node.position = Self.arcPoint(t: t, start: point, control: control, end: end)
            node.setScale(max(1 - t, 0))
        }
        node.run(.sequence([flight, .removeFromParent()]), withKey: "fly")
        try? await Task.sleep(nanoseconds: UInt64(span * 1_000_000_000))
        node.removeFromParent()
    }

    /// Mirrors `MinigameResultOverlay`'s `CoinArcFlight`: hold, then arc every coin into
    /// the bottom-left corner while shrinking away.
    func flyToCorner(
        holdSeconds: TimeInterval = 1.0,
        flightSeconds: TimeInterval = 0.75
    ) async {
        guard let scene, !coins.isEmpty else { return }
        try? await Task.sleep(nanoseconds: UInt64(max(holdSeconds, 0) * 1_000_000_000))

        let span = max(flightSeconds, 0.01)
        let arcHeight = scene.size.height * 0.22
        let end = CGPoint.zero
        for coin in coins {
            coin.removeAction(forKey: "bob")
            coin.removeAction(forKey: "pop")
            // Ensure the coin is on-screen before the arc even if pop never ticked.
            coin.alpha = 1
            let start = coin.position
            // SpriteKit's Y grows upward, so the control point sits *above* both ends.
            // The SwiftUI original subtracts for the same shape.
            let control = CGPoint(
                x: start.x + (end.x - start.x) * 0.75,
                y: max(start.y, end.y) + arcHeight
            )
            let flight = SKAction.customAction(withDuration: span) { node, elapsed in
                let raw = min(max(CGFloat(elapsed) / CGFloat(span), 0), 1)
                let t = raw * raw * (3 - 2 * raw)
                node.position = Self.arcPoint(t: t, start: start, control: control, end: end)
                node.setScale(max(1 - t, 0))
            }
            coin.run(.sequence([flight, .removeFromParent()]), withKey: "fly")
        }
        try? await Task.sleep(nanoseconds: UInt64(span * 1_000_000_000))
        coins = []
    }

    /// Quadratic Bezier, matching the overlay's control-point placement.
    static func arcPoint(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let inv = 1 - t
        return CGPoint(
            x: inv * inv * start.x + 2 * inv * t * control.x + t * t * end.x,
            y: inv * inv * start.y + 2 * inv * t * control.y + t * t * end.y
        )
    }

    func teardown() {
        root.removeAllActions()
        root.removeAllChildren()
        root.removeFromParent()
        coins = []
    }

    private func makeCoinNode(at point: CGPoint) -> SKSpriteNode {
        let size = CGSize(width: side, height: side)
        let node: SKSpriteNode
        if let image = ScoreCoinIcon.uiImage() {
            node = SKSpriteNode(texture: SKTexture(image: image), size: size)
        } else {
            node = SKSpriteNode(color: .systemOrange, size: size)
        }
        node.position = point
        node.setScale(0.1)
        node.alpha = 0
        return node
    }
}
