import UIKit
import SpriteKit

/// Health / energy HUD art from `items.yaml` (replaces SF Symbol heart / bolt).
enum HudVitalIcon {
    case health
    case energy

    @MainActor
    private static var cached: [HudVitalIcon: UIImage] = [:]
    @MainActor
    private static var didAttemptLoad: Set<HudVitalIcon> = []

    /// Upright item UIImage, or nil when the sprite is missing / malformed.
    @MainActor
    func uiImage() -> UIImage? {
        if Self.didAttemptLoad.contains(self) { return Self.cached[self] }
        Self.didAttemptLoad.insert(self)
        let image = Self.load(id: itemID)
        Self.cached[self] = image
        return image
    }

    /// UIKit image view sized to `side`. Falls back to the prior SF Symbol glyph.
    @MainActor
    func makeImageView(side: CGFloat) -> UIImageView {
        let image: UIImage
        if let sprite = uiImage() {
            image = sprite
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: side, weight: .regular)
            image = (UIImage(systemName: fallbackSystemName, withConfiguration: config)?
                .withTintColor(fallbackTint, renderingMode: .alwaysOriginal))
                ?? UIImage()
        }
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: side),
            view.heightAnchor.constraint(equalToConstant: side),
        ])
        return view
    }

    /// Still frame for stacking multiple icons at `side` (same slot size as before).
    @MainActor
    func makeUIImage(pointSize: CGFloat) -> UIImage? {
        if let sprite = uiImage() {
            return sprite
        }
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return UIImage(systemName: fallbackSystemName, withConfiguration: config)?
            .withTintColor(fallbackTint, renderingMode: .alwaysOriginal)
    }

    private var itemID: String {
        switch self {
        case .health: return "health"
        case .energy: return "energy"
        }
    }

    private var fallbackSystemName: String {
        switch self {
        case .health: return "heart.fill"
        case .energy: return "bolt.fill"
        }
    }

    private var fallbackTint: UIColor {
        switch self {
        case .health: return .systemRed
        case .energy: return .systemYellow
        }
    }

    @MainActor
    private static func load(id: String) -> UIImage? {
        guard let items = try? ItemsConfig.loadFromBundle(),
              let config = items.spriteConfig(id: id),
              case let .sheet(sheet, atlas)? = config.animations["idle"]
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
        // Undo the SpriteKit prep flip, exactly as `SpriteLibrary.uiImage` does.
        let upright = SpriteSheetLoader.flipAroundXAxis(frame.texture.cgImage())
        return UIImage(cgImage: upright, scale: 1, orientation: .up).preparedForScreen()
    }
}
