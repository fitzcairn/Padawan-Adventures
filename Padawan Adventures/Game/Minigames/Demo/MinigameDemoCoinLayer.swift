import SpriteKit

@MainActor
final class MinigameDemoCoinLayer {
    private let root = SKNode()
    private var coins: [SKSpriteNode] = []
    private let side: CGFloat
    private weak var scene: SKScene?

    init(scene: SKScene, side: CGFloat = 44) {
        self.scene = scene
        self.side = side
        root.zPosition = MinigameDemoCursor.zPosition - 100
        scene.addChild(root)
    }

    var count: Int { coins.count }

    func dropCoin(at point: CGPoint) {
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
        root.addChild(node)
        coins.append(node)

        node.run(.group([
            .fadeIn(withDuration: 0.2),
            .sequence([
                .scale(to: 1.15, duration: 0.18),
                .scale(to: 1.0, duration: 0.10),
            ]),
        ]))
        node.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 6, duration: 0.6),
            .moveBy(x: 0, y: -6, duration: 0.6),
        ])), withKey: "bob")
    }

    /// Gathers the coins into a row near the top with a total, mirroring
    /// `MinigameResultOverlay`'s coin arc.
    func tally(total: Int? = nil) async {
        guard let scene, !coins.isEmpty else { return }
        let shown = total ?? coins.count
        let spacing = side * 1.2
        let width = spacing * CGFloat(coins.count - 1)
        let y = scene.size.height * 0.82
        let startX = scene.size.width * 0.5 - width * 0.5

        // Kick off SKActions, then sleep for their duration. Awaiting
        // `node.run(...)` hangs forever when the scene is not presented
        // (unit tests build a bare SKScene with no view / update loop).
        let gatherDuration: TimeInterval = 0.45
        for (index, coin) in coins.enumerated() {
            coin.removeAction(forKey: "bob")
            let move = SKAction.move(
                to: CGPoint(x: startX + spacing * CGFloat(index), y: y),
                duration: gatherDuration
            )
            move.timingMode = .easeInEaseOut
            // Completion-handler overload (not the async `run`) so we don't
            // hang when the scene has no update loop.
            coin.run(move, completion: {})
        }
        try? await Task.sleep(nanoseconds: UInt64(gatherDuration * 1_000_000_000))
        try? await Task.sleep(nanoseconds: 500_000_000)

        let fadeDuration: TimeInterval = 0.25
        let label = SKLabelNode(text: "x\(shown)")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = side * 0.8
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: startX + width + spacing, y: y)
        label.alpha = 0
        root.addChild(label)
        label.run(.fadeIn(withDuration: fadeDuration), completion: {})
        try? await Task.sleep(nanoseconds: UInt64(fadeDuration * 1_000_000_000))
    }

    func teardown() {
        root.removeAllActions()
        root.removeAllChildren()
        root.removeFromParent()
        coins = []
    }
}
