import SpriteKit
import UIKit

/// Loads a single upright still frame for an `items.yaml` id, for static UI icons.
///
/// Fallback path only: at runtime `AppSession` seeds these icons from `SpriteLibrary`.
@MainActor
enum ItemIconLoader {
    private static var cachedItems: ItemsConfig?

    static func firstFrameImage(itemID: String, animationName: String = "idle") -> UIImage? {
        let items: ItemsConfig
        if let cachedItems {
            items = cachedItems
        } else if let loaded = try? ItemsConfig.loadFromBundle() {
            cachedItems = loaded
            items = loaded
        } else {
            return nil
        }

        guard let config = items.spriteConfig(id: itemID),
              case let .sheet(sheet, atlas)? = config.animations[animationName]
        else {
            return nil
        }

        let animation = try? SpriteSheetLoader.loadAnimation(
            sheet: sheet,
            atlas: atlas,
            root: config.root,
            chromaKey: config.chromaKey,
            chromaKeyTolerance: config.chromaKeyTolerance,
            chromaKeyFeather: config.chromaKeyFeather,
            chromaKeySmooth: config.chromaKeySmooth,
            trim: config.trim
        )
        guard let frame = animation?.frames.first else { return nil }
        let upright = SpriteSheetLoader.flipAroundXAxis(frame.texture.cgImage())
        return UIImage(cgImage: upright, scale: 1, orientation: .up).preparedForScreen()
    }
}
