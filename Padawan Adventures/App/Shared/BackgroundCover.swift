import CoreGraphics

/// Uniform cover sizing: center the image, scale until the viewport is fully covered.
enum BackgroundCover {
    /// Display size that covers `viewport` while preserving `image` aspect ratio.
    static func displaySize(image: CGSize, viewport: CGSize) -> CGSize {
        let imageWidth = max(image.width, 1)
        let imageHeight = max(image.height, 1)
        let viewportWidth = max(viewport.width, 1)
        let viewportHeight = max(viewport.height, 1)
        let scale = max(viewportWidth / imageWidth, viewportHeight / imageHeight)
        return CGSize(width: imageWidth * scale, height: imageHeight * scale)
    }
}
