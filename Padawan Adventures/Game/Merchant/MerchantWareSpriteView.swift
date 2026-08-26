import SwiftUI
import UIKit

/// First-frame still of a merchant ware, sized by the parent.
struct MerchantWareSpriteView: View {
    let itemID: String
    let sprite: SpriteConfig
    var showsShadow: Bool = false
    var showsGleam: Bool = true

    var body: some View {
        let image = MerchantWareIcon.image(id: itemID, sprite: sprite)
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .compositingGroup()
                    .shadow(
                        color: showsShadow ? Color.black.opacity(0.55) : .clear,
                        radius: showsShadow ? 8 : 0,
                        x: 0,
                        y: showsShadow ? 6 : 0
                    )
                if showsGleam {
                    GeometryReader { geo in
                        SpiralGleamView(
                            isEnabled: true,
                            diameter: min(geo.size.width, geo.size.height),
                            image: image,
                            appliesRackRotation: false
                        )
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Cached upright stills for shop / inventory / inspect.
@MainActor
enum MerchantWareIcon {
    private static var cache: [String: UIImage] = [:]

    static func image(id: String, sprite: SpriteConfig) -> UIImage? {
        if let cached = cache[id] { return cached }
        let loaded = ItemIconLoader.firstFrameImage(sprite: sprite)
        if let loaded {
            cache[id] = loaded
        }
        return loaded
    }

    static func pixelSize(id: String, sprite: SpriteConfig) -> CGSize {
        image(id: id, sprite: sprite)?.size ?? CGSize(width: 1, height: 1)
    }
}
