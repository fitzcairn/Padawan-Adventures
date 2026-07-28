import SpriteKit
import UIKit

/// Session-scoped cache of single still frames sliced from sprite sheets, for UI icons.
///
/// Unlike `SpriteLibrary` this keeps only frame 0 per id, so an icon costs one 256x256
/// image instead of a full 25-frame clip.
@MainActor
final class SpriteIconLibrary {
    private var images: [String: UIImage] = [:]
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Number of cached icons (tests / diagnostics).
    var count: Int { images.count }

    func uiImage(id: String) -> UIImage? {
        images[id]
    }

    /// Slices the first frame of `config`'s `animationName` clip and caches it under `id`.
    ///
    /// Missing or malformed assets are skipped so callers fall back to a glyph.
    func ensureLoaded(_ config: SpriteConfig, id: String, animationName: String = "idle") async {
        guard images[id] == nil else { return }
        guard case .sheet(let sheet, let atlas)? = config.animations[animationName] else { return }

        let animation = try? SpriteSheetLoader.loadAnimation(
            sheet: sheet,
            atlas: atlas,
            root: config.root,
            chromaKey: config.chromaKey,
            chromaKeyTolerance: config.chromaKeyTolerance,
            chromaKeyFeather: config.chromaKeyFeather,
            chromaKeySmooth: config.chromaKeySmooth,
            bundle: bundle
        )
        guard let frame = animation?.frames.first else { return }
        // Undo the SpriteKit prep flip, exactly as `SpriteLibrary.uiImage` does.
        let upright = SpriteSheetLoader.flipAroundXAxis(frame.texture.cgImage())
        let image = UIImage(cgImage: upright, scale: 1, orientation: .up)
        images[id] = image.preparedForScreen()
        await Task.yield()
    }
}
