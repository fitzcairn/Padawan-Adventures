import SpriteKit
import UIKit

/// Baked socket faceplate variants for word-plug (`Sprites/Gate/StartingSoundGate/sockets-*`).
@MainActor
enum GateWordPlugSocketSprites {
    private static var cached: [SKTexture]?
    private static var didAttemptLoad = false

    /// Loads all socket frame textures (random pick via `randomTexture`).
    static func load(bundle: Bundle = .main) -> [SKTexture]? {
        if bundle === Bundle.main {
            if didAttemptLoad { return cached }
            didAttemptLoad = true
        }

        let root = "Sprites/Gate/StartingSoundGate"
        let sheetName = "sockets-spritesheet"
        let atlasName = "sockets-atlas"

        let sheetURL: URL
        let atlasURL: URL
        do {
            sheetURL = try SpriteSheetLoader.resourceURL(
                named: sheetName,
                extensions: ["png", "jpg", "jpeg"],
                root: root,
                bundle: bundle
            )
            atlasURL = try SpriteSheetLoader.resourceURL(
                named: atlasName,
                extensions: ["json"],
                root: root,
                bundle: bundle
            )
        } catch {
            return nil
        }

        guard let atlasData = try? Data(contentsOf: atlasURL),
              let atlas = try? SpriteAtlas.decode(from: atlasData),
              let uiImage = UIImage(contentsOfFile: sheetURL.path)
                ?? (try? Data(contentsOf: sheetURL)).flatMap(UIImage.init(data:)),
              let cgImage = uiImage.cgImage
        else {
            return nil
        }

        let ordered = atlas.orderedFrames
        guard !ordered.isEmpty else { return nil }

        let sheetW = cgImage.width
        let sheetH = cgImage.height
        guard sheetW > 0, sheetH > 0 else { return nil }

        let parent = SKTexture(image: UIImage(cgImage: cgImage, scale: 1, orientation: .up))
        SpriteSheetLoader.prepareTextureForScaledDisplay(parent)

        var textures: [SKTexture] = []
        textures.reserveCapacity(ordered.count)
        for entry in ordered {
            let frame = entry.frame
            guard frame.w > 0, frame.h > 0,
                  frame.x >= 0, frame.y >= 0,
                  frame.x + frame.w <= sheetW,
                  frame.y + frame.h <= sheetH
            else {
                continue
            }
            textures.append(
                SpriteSheetLoader.makeSubrectTexture(
                    x: frame.x,
                    y: frame.y,
                    w: frame.w,
                    h: frame.h,
                    sheetWidth: sheetW,
                    sheetHeight: sheetH,
                    parent: parent
                )
            )
        }
        guard !textures.isEmpty else { return nil }
        if bundle === Bundle.main {
            cached = textures
        }
        return textures
    }

    /// Drops the cached textures so the next `load()` re-decodes from the bundle.
    static func release() {
        cached = nil
        didAttemptLoad = false
    }

    static func randomTexture(using rng: inout some RandomNumberGenerator) -> SKTexture? {
        guard let textures = load(), let texture = textures.randomElement(using: &rng) else {
            return nil
        }
        return texture
    }

    /// Aspect-fit socket into a square of `side`.
    static func sprite(texture: SKTexture, side: CGFloat) -> SKSpriteNode? {
        guard side > 0 else { return nil }
        let node = SKSpriteNode(texture: texture)
        let texSize = texture.size()
        let maxDim = max(texSize.width, texSize.height)
        guard maxDim > 0 else { return nil }
        let scale = side / maxDim
        node.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
        node.isUserInteractionEnabled = false
        return node
    }
}
