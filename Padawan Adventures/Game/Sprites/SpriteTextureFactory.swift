import CoreGraphics
import Foundation
import SpriteKit
import UIKit

extension SpriteSheetLoader {
    /// Linear filtering for scaled display. Mipmaps off — they shimmer when swapping anim frames.
    static func prepareTextureForScaledDisplay(_ texture: SKTexture) {
        texture.filteringMode = .linear
        texture.usesMipmaps = false
    }

    /// Builds a frame texture from an atlas crop (exact pixels, no extra redraw pass).
    static func makeFrameTexture(from image: CGImage) -> SKTexture {
        let texture = SKTexture(image: UIImage(cgImage: image, scale: 1, orientation: .up))
        prepareTextureForScaledDisplay(texture)
        return texture
    }

    /// Normalized sub-rect of `parent` for an atlas pixel rect (top-left origin → SpriteKit bottom-left).
    static func makeSubrectTexture(
        x: Int,
        y: Int,
        w: Int,
        h: Int,
        sheetWidth: Int,
        sheetHeight: Int,
        parent: SKTexture
    ) -> SKTexture {
        let normalized = CGRect(
            x: CGFloat(x) / CGFloat(sheetWidth),
            y: 1.0 - CGFloat(y + h) / CGFloat(sheetHeight),
            width: CGFloat(w) / CGFloat(sheetWidth),
            height: CGFloat(h) / CGFloat(sheetHeight)
        )
        let texture = SKTexture(rect: normalized, in: parent)
        prepareTextureForScaledDisplay(texture)
        return texture
    }
}
