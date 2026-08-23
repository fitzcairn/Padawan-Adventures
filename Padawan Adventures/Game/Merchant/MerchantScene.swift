import SpriteKit
import UIKit

/// Shop backdrop. Character sprites stay in the world; the minigame does not draw them.
final class MerchantScene: MinigameScene {
    let backgroundImage: UIImage?

    init(size: CGSize, backgroundImage: UIImage?) {
        self.backgroundImage = backgroundImage
        super.init(size: size)
    }

    override func buildContent() {
        rebuildLayout()
    }

    override func rebuildLayout() {
        preservingDemoOverlays {
            removeAllChildren()
            addBackground()
        }
    }

    private func addBackground() {
        guard let backgroundImage else { return }
        let rect = MerchantWares.aspectFit(
            imageSize: backgroundImage.size,
            in: size
        )
        let node = SKSpriteNode(texture: SKTexture(image: backgroundImage))
        node.size = rect.size
        node.position = CGPoint(x: rect.midX, y: rect.midY)
        node.zPosition = 0
        node.name = "merchantBackground"
        addChild(node)
    }
}
