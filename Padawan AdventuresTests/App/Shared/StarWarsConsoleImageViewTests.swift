import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct StarWarsConsoleImageViewTests {
    /// Word-plug CRTs must show the real illustration, not a blue template silhouette.
    @Test func illustrationKeepsSourceHueInsteadOfTemplateBlue() {
        let image = solidImage(color: .red, side: 64)
        let texture = StarWarsConsoleImageView.makeTexture(
            image: image,
            maskedText: "_og",
            size: CGSize(width: 240, height: 80),
            scale: 2
        )
        let cgImage = texture.cgImage()
        // Illustration sits on the leading side of the screen; sample well inside that half.
        let sample = pixel(
            in: cgImage,
            x: Int(CGFloat(cgImage.width) * 0.22),
            y: Int(CGFloat(cgImage.height) * 0.50)
        )
        expectKeepsRedHue(sample)
    }

    /// Pit prompt CRTs (starting/ending-sound-pit) must keep the real illustration too —
    /// not a full blue phosphor wash.
    @Test func promptIllustrationKeepsSourceHueInsteadOfPhosphorBlue() {
        let image = solidImage(color: .red, side: 64)
        let texture = StarWarsConsolePromptView.makeTexture(
            image: image,
            wordBandFraction: 0.28,
            gapFraction: 0.04,
            size: CGSize(width: 180, height: 220),
            scale: 2
        )
        let cgImage = texture.cgImage()
        // Picture sits in the upper portion above the transparent word band.
        let sample = pixel(
            in: cgImage,
            x: Int(CGFloat(cgImage.width) * 0.50),
            y: Int(CGFloat(cgImage.height) * 0.32)
        )
        expectKeepsRedHue(sample)
    }

    private func expectKeepsRedHue(_ sample: (r: CGFloat, g: CGFloat, b: CGFloat)) {
        #expect(sample.r > 0.45)
        #expect(sample.r > sample.g + 0.15)
        #expect(sample.r > sample.b + 0.15)
    }

    private func solidImage(color: UIColor, side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let clampedX = min(max(x, 0), image.width - 1)
        let clampedY = min(max(y, 0), image.height - 1)
        var rgba: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &rgba,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(
            image,
            in: CGRect(
                x: -clampedX,
                y: -(image.height - 1 - clampedY),
                width: image.width,
                height: image.height
            )
        )
        return (
            r: CGFloat(rgba[0]) / 255,
            g: CGFloat(rgba[1]) / 255,
            b: CGFloat(rgba[2]) / 255
        )
    }
}
