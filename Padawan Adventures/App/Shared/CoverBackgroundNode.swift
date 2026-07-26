import SpriteKit

/// Screen-fixed cover background for SpriteKit scenes (does not pan with the world).
final class CoverBackgroundNode: SKSpriteNode {
    static let nodeName = "coverBackground"
    static let defaultZPosition: CGFloat = -1000

    private var imageSize: CGSize = .zero

    convenience init(texture: SKTexture) {
        let size = texture.size()
        self.init(texture: texture, color: .clear, size: size)
        name = Self.nodeName
        zPosition = Self.defaultZPosition
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageSize = size
    }

    func layout(viewport: CGSize) {
        size = BackgroundCover.displaySize(image: imageSize, viewport: viewport)
        position = .zero
    }
}

extension SKScene {
    /// Installs or replaces a cover background from `library` for `name`.
    @MainActor
    func setCoverBackground(named name: String, library: BackgroundLibrary) {
        clearCoverBackground()
        guard let texture = library.texture(named: name) else { return }
        let node = CoverBackgroundNode(texture: texture)
        node.layout(viewport: size)
        addChild(node)
    }

    func clearCoverBackground() {
        childNode(withName: CoverBackgroundNode.nodeName)?.removeFromParent()
    }

    /// Re-applies cover sizing after the scene size changes.
    func layoutCoverBackground() {
        guard let node = childNode(withName: CoverBackgroundNode.nodeName) as? CoverBackgroundNode else {
            return
        }
        node.layout(viewport: size)
    }
}
