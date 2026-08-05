import SpriteKit
import UIKit

/// Off/on switch textures for letter-match buttons (`Sprites/Gate/grapheme_match/switch-*`).
@MainActor
enum GateGraphemeMatchSwitchSprites {
    struct Textures {
        let off: SKTexture
        let on: SKTexture
    }

    private static var cached: Textures?
    private static var didAttemptLoad = false

    /// Loads baked (preferred) or source switch sheet; frame 0 = OFF, frame 1 = ON.
    static func load(bundle: Bundle = .main) -> Textures? {
        if bundle === Bundle.main {
            if didAttemptLoad { return cached }
            didAttemptLoad = true
        }

        let root = "Sprites/Gate/grapheme_match"
        let sheetName = "switch-spritesheet"
        let atlasName = "switch-atlas"

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
              let uiImage = UIImage(contentsOfFile: sheetURL.path) ?? (try? Data(contentsOf: sheetURL)).flatMap(UIImage.init(data:)),
              let cgImage = uiImage.cgImage
        else {
            return nil
        }

        let ordered = atlas.orderedFrames
        guard ordered.count >= 2 else { return nil }

        // Baked sheets already flood-cleared exterior black. Unbaked fallback keeps
        // the source as-is (global chroma would punch holes in dark button recesses).
        let keyedImage = cgImage

        let sheetW = keyedImage.width
        let sheetH = keyedImage.height
        guard sheetW > 0, sheetH > 0 else { return nil }

        let parent = SKTexture(image: UIImage(cgImage: keyedImage, scale: 1, orientation: .up))
        SpriteSheetLoader.prepareTextureForScaledDisplay(parent)

        func texture(at index: Int) -> SKTexture? {
            let frame = ordered[index].frame
            guard frame.w > 0, frame.h > 0,
                  frame.x >= 0, frame.y >= 0,
                  frame.x + frame.w <= sheetW,
                  frame.y + frame.h <= sheetH
            else {
                return nil
            }
            return SpriteSheetLoader.makeSubrectTexture(
                x: frame.x,
                y: frame.y,
                w: frame.w,
                h: frame.h,
                sheetWidth: sheetW,
                sheetHeight: sheetH,
                parent: parent
            )
        }

        guard let off = texture(at: 0), let on = texture(at: 1) else { return nil }
        let result = Textures(off: off, on: on)
        if bundle === Bundle.main {
            cached = result
        }
        return result
    }

    /// Aspect-fit switch into a square of `side`.
    static func sprite(texture: SKTexture, side: CGFloat) -> SKSpriteNode? {
        guard side > 0 else { return nil }
        let node = SKSpriteNode(texture: texture)
        let texSize = texture.size()
        let maxDim = max(texSize.width, texSize.height)
        guard maxDim > 0 else { return nil }
        let scale = side / maxDim
        node.size = CGSize(width: texSize.width * scale, height: texSize.height * scale)
        return node
    }
}
