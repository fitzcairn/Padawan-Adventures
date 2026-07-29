import SpriteKit
import SwiftUI
import UIKit

/// Score / currency coin art from `items.yaml` `coin` sprite (replaces SF Symbol stars).
enum ScoreCoinIcon {
    @MainActor
    private static var cached: UIImage?
    @MainActor
    private static var didAttemptLoad = false

    /// Seeds the cache from a bootstrap-loaded sprite. Ignores `nil` so the lazy fallback remains.
    @MainActor
    static func seed(_ image: UIImage?) {
        guard let image else { return }
        cached = image
        didAttemptLoad = true
    }

    /// Upright coin UIImage, or nil when the sprite is missing / malformed.
    @MainActor
    static func uiImage() -> UIImage? {
        if didAttemptLoad { return cached }
        didAttemptLoad = true
        cached = load()
        return cached
    }

    /// SwiftUI coin sized to `side` (square, aspect-fit). Falls back to orange star glyph.
    struct Image: View {
        var side: CGFloat

        var body: some View {
            Group {
                if let image = ScoreCoinIcon.uiImage() {
                    SwiftUI.Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    SwiftUI.Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: side * 0.9, weight: .semibold))
                }
            }
            .frame(width: side, height: side)
        }
    }

    /// UIKit image view sized to `side`. Falls back to orange star glyph.
    @MainActor
    static func makeImageView(side: CGFloat) -> UIImageView {
        let image: UIImage
        if let coin = uiImage() {
            image = coin
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: side, weight: .semibold)
            image = (UIImage(systemName: "star.fill", withConfiguration: config)?
                .withTintColor(.systemOrange, renderingMode: .alwaysOriginal))
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

    @MainActor
    private static func load() -> UIImage? {
        ItemIconLoader.firstFrameImage(itemID: "coin")
    }
}
