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

        for (index, coin) in coins.enumerated() {
            coin.removeAction(forKey: "bob")
            let move = SKAction.move(
                to: CGPoint(x: startX + spacing * CGFloat(index), y: y),
                duration: 0.45
            )
            move.timingMode = .easeInEaseOut
            await coin.run(move)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)

        let label = SKLabelNode(text: "x\(shown)")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = side * 0.8
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: startX + width + spacing, y: y)
        label.alpha = 0
        root.addChild(label)
        await label.run(.fadeIn(withDuration: 0.25))
    }

    func teardown() {
        root.removeAllActions()
        root.removeAllChildren()
        root.removeFromParent()
        coins = []
    }
}
