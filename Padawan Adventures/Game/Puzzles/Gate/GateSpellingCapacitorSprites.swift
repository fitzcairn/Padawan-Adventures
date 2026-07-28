import SpriteKit
import UIKit

/// Capacitor token art for the spelling gate minigame (`Sprites/Gate/spelling/capacitor.png`).
enum GateSpellingCapacitorSprites {
    /// Loads the capacitor texture, clearing the solid black backdrop.
    static func load(bundle: Bundle = .main) -> SKTexture? {
        let root = "Sprites/Gate/spelling"
        let url: URL
        do {
            url = try SpriteSheetLoader.resourceURL(
                named: "capacitor",
                extensions: ["png"],
                root: root,
                bundle: bundle
            )
        } catch {
            return nil
        }

        guard let uiImage = UIImage(contentsOfFile: url.path)
            ?? (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)),
              let cgImage = uiImage.cgImage
        else {
            return nil
        }

        let keyed: CGImage
        if SpriteSheetLoader.isBakedResource(at: url) {
            keyed = cgImage
        } else if let rgb = SpriteSheetLoader.parseHexRGB("#000000") {
            // Exterior is near-black; keep the darker outline (channel values ~10+).
            keyed = SpriteSheetLoader.applyChromaKey(
                to: cgImage,
                key: rgb,
                tolerance: 6,
                feather: 4
            )
        } else {
            keyed = cgImage
        }

        let texture = SKTexture(image: UIImage(cgImage: keyed, scale: 1, orientation: .up))
        SpriteSheetLoader.prepareTextureForScaledDisplay(texture)
        return texture
    }

    /// Aspect-fit capacitor into a square of `side`.
    static func sprite(texture: SKTexture, side: CGFloat) -> SKSpriteNode? {
        guard side > 0 else { return nil }
        let node = SKSpriteNode(texture: texture)
        let texSize = texture.size()
        let maxDim = max(texSize.width, texSize.height)
        guard maxDim > 0 else { return nil }
        let scale = side / maxDim
        node.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
        node.name = "capacitor"
        node.isUserInteractionEnabled = false
        return node
    }

    /// Letter sits on the flat top face (slightly above the sprite center).
    static func letterOffsetY(for spriteHeight: CGFloat) -> CGFloat {
        spriteHeight * 0.18
    }
}
