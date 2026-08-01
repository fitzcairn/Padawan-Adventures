import CoreGraphics
import Foundation
import SpriteKit
import UIKit

extension SpriteSheetLoader {
    /// Crops every frame to the union of opaque bounds so feet align across the clip.
    static func trimToSharedOpaqueBounds(_ images: [CGImage]) -> [CGImage] {
        guard !images.isEmpty else { return images }

        var union = CGRect.null
        for image in images {
            guard let bounds = opaqueContentBounds(of: image) else { continue }
            union = union.union(bounds)
        }
        guard !union.isNull, !union.isEmpty else { return images }

        let crop = union.integral
        return images.map { image in
            let clamped = crop.intersection(
                CGRect(x: 0, y: 0, width: image.width, height: image.height)
            ).integral
            guard clamped.width >= 1, clamped.height >= 1,
                  let trimmed = image.cropping(to: clamped) else {
                return image
            }
            return trimmed
        }
    }

    /// Axis-aligned bounds of pixels with alpha above `alphaThreshold` (image top-left origin).
    static func opaqueContentBounds(
        of image: CGImage,
        alphaThreshold: UInt8 = 1
    ) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // After the Y-flip draw, buffer row 0 is the image bottom (Quartz).
        var minX = width
        var minBufferY = height
        var maxX = -1
        var maxBufferY = -1

        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * bytesPerPixel
                if data[i + 3] >= alphaThreshold {
                    minX = min(minX, x)
                    minBufferY = min(minBufferY, y)
                    maxX = max(maxX, x)
                    maxBufferY = max(maxBufferY, y)
                }
            }
        }

        guard maxX >= minX, maxBufferY >= minBufferY else { return nil }

        // Convert to image top-left space used by CGImage.cropping(to:).
        let minY = height - 1 - maxBufferY
        let maxY = height - 1 - minBufferY
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
