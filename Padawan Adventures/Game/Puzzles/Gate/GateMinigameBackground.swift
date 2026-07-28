import SpriteKit
import UIKit

/// Full-width, aspect-preserving backgrounds for gate minigames.
enum GateMinigameBackground {
    /// Letter-match art under `Sprites/Gate/letter_match/letter_match-bg.png`.
    static func letterMatch(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "letter_match-bg", root: "Sprites/Gate/letter_match", sceneSize: sceneSize)
    }

    /// Spelling art under `Sprites/Gate/spelling/spelling-bg.png`.
    static func spelling(sceneSize: CGSize) -> SKSpriteNode? {
        makeNode(named: "spelling-bg", root: "Sprites/Gate/spelling", sceneSize: sceneSize)
    }

    /// Scales the image to `sceneSize.width`, keeps aspect ratio, and centers it.
    private static func makeNode(
        named name: String,
        root: String,
        sceneSize: CGSize
    ) -> SKSpriteNode? {
        guard sceneSize.width > 1 else { return nil }

        let url: URL
        do {
            url = try SpriteSheetLoader.resourceURL(
                named: name,
                extensions: ["png"],
                root: root,
                bundle: .main
            )
        } catch {
            return nil
        }

        guard let uiImage = UIImage(contentsOfFile: url.path) ?? (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)),
              let cgImage = uiImage.cgImage
        else {
            return nil
        }

        let texture = SKTexture(image: UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        SpriteSheetLoader.prepareTextureForScaledDisplay(texture)

        let aspect = texture.size().height / max(texture.size().width, 1)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: sceneSize.width, height: sceneSize.width * aspect)
        node.position = CGPoint(x: sceneSize.width * 0.5, y: sceneSize.height * 0.5)
        node.zPosition = 0
        node.name = "background"
        node.isUserInteractionEnabled = false
        return node
    }
}
