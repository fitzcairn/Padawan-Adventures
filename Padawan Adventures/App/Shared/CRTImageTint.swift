import CoreImage
import SwiftUI
import UIKit

/// CRT phosphor treatment for word illustrations: a luminance-preserving blue
/// monochrome, so the art still reads instead of flattening to a template silhouette.
enum CRTImageTint {
    private static let context = CIContext()

    /// Runs once per plate build (once per round), so no cache is needed.
    static func phosphor(
        _ image: UIImage,
        tint: UIColor = UIColor(StarWarsConsolePalette.crtBlue)
    ) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)
        guard let mono = CIFilter(
            name: "CIColorMonochrome",
            parameters: [
                kCIInputImageKey: input,
                kCIInputColorKey: CIColor(color: tint),
                kCIInputIntensityKey: 1.0,
            ]
        )?.outputImage,
        let output = context.createCGImage(mono, from: input.extent) else {
            return image
        }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
    }
}
