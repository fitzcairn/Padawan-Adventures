import CoreGraphics
import Foundation
import UIKit

enum PlayerAvatarImage {
    static let thumbnailSize = CGSize(width: 200, height: 200)

    /// Crops a centered square, optionally sized as a fraction of the shorter side, then scales to 200×200 JPEG.
    nonisolated static func makeThumbnailJPEG(
        from image: UIImage,
        circleDiameterRelativeToMinSide: CGFloat? = nil
    ) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        let minSide = min(width, height)
        let cropSide: CGFloat
        if let fraction = circleDiameterRelativeToMinSide {
            cropSide = min(minSide, minSide * fraction)
        } else {
            cropSide = minSide
        }

        let originX = (width - cropSide) / 2
        let originY = (height - cropSide) / 2
        let cropRect = CGRect(x: originX, y: originY, width: cropSide, height: cropSide)
            .integral

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        let croppedImage = UIImage(cgImage: cropped, scale: 1, orientation: image.imageOrientation)
        let normalized = normalizedUpImage(croppedImage)
        let scaled = scale(normalized, to: thumbnailSize)
        return scaled.jpegData(compressionQuality: 0.85)
    }

    /// Diameter for a circle whose area is 80% of a rect with the given size.
    nonisolated static func circleDiameter(forPreviewSize size: CGSize) -> CGFloat {
        let area = size.width * size.height
        guard area > 0 else { return 0 }
        return 2 * sqrt(0.8 * area / .pi)
    }

    /// Fraction of the shorter preview side occupied by the 80%-area circle diameter.
    nonisolated static func circleDiameterFractionOfMinSide(forPreviewSize size: CGSize) -> CGFloat {
        let minSide = min(size.width, size.height)
        guard minSide > 0 else { return 0 }
        return circleDiameter(forPreviewSize: size) / minSide
    }

    nonisolated static func uiImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }

    private nonisolated static func scale(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private nonisolated static func normalizedUpImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
