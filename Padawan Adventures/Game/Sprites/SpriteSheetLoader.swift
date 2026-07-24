import CoreGraphics
import Foundation
import SpriteKit
import UIKit

enum SpriteSheetLoader {
    /// Loads a spritesheet + atlas and returns chroma-keyed animation frames.
    static func loadAnimation(
        sheet: String,
        atlas: String,
        root: String,
        chromaKey: String?,
        bundle: Bundle = .main
    ) throws -> SpriteAnimation {
        let sheetURL = try resourceURL(
            named: sheet,
            extensions: ["png", "jpg", "jpeg"],
            root: root,
            bundle: bundle
        )
        let atlasURL = try resourceURL(
            named: atlas,
            extensions: ["json"],
            root: root,
            bundle: bundle
        )

        let atlasData = try Data(contentsOf: atlasURL)
        let atlasDoc = try SpriteAtlas.decode(from: atlasData)

        let sheetData = try Data(contentsOf: sheetURL)
        guard let uiImage = UIImage(contentsOfFile: sheetURL.path) ?? UIImage(data: sheetData),
              let cgImage = uiImage.cgImage else {
            throw SpriteLoadError.invalidImage(sheet)
        }

        let keyedImage: CGImage
        if let chromaKey, let rgb = parseHexRGB(chromaKey) {
            keyedImage = applyChromaKey(to: cgImage, key: rgb)
        } else {
            keyedImage = cgImage
        }

        let sheetWidth = keyedImage.width
        let sheetHeight = keyedImage.height
        guard sheetWidth > 0, sheetHeight > 0 else {
            throw SpriteLoadError.invalidImage(sheet)
        }

        let durations = atlasDoc.frameDurationsSeconds()
        let ordered = atlasDoc.orderedFrames

        var croppedFrames: [CGImage] = []
        croppedFrames.reserveCapacity(ordered.count)

        for entry in ordered {
            let rect = entry.frame
            let crop = CGRect(
                x: rect.x,
                y: rect.y,
                width: rect.w,
                height: rect.h
            )
            guard crop.minX >= 0, crop.minY >= 0,
                  crop.maxX <= CGFloat(sheetWidth) + 0.5,
                  crop.maxY <= CGFloat(sheetHeight) + 0.5,
                  let cropped = keyedImage.cropping(to: crop.integral) else {
                continue
            }
            croppedFrames.append(cropped)
        }

        guard !croppedFrames.isEmpty else {
            throw SpriteLoadError.noFrames(atlas)
        }

        // Trim shared transparent padding so the bottommost opaque pixel sits on the
        // texture edge (and thus on the tile with the node's feet anchor).
        let trimmedFrames = trimToSharedOpaqueBounds(croppedFrames)

        var frames: [SpriteFrame] = []
        frames.reserveCapacity(trimmedFrames.count)

        for (index, image) in trimmedFrames.enumerated() {
            let texture = uprightTexture(from: image)
            let duration = index < durations.count
                ? durations[index]
                : (1.0 / SpriteAtlas.fallbackFramesPerSecond)
            frames.append(SpriteFrame(texture: texture, duration: max(duration, 0.000_001)))
        }

        return SpriteAnimation(frames: frames)
    }

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

    /// Linear filtering + mipmaps so downscaled billboards stay smooth.
    static func prepareTextureForScaledDisplay(_ texture: SKTexture) {
        texture.filteringMode = .linear
        texture.usesMipmaps = true
    }

    /// Redraws a cropped frame through UIKit so SpriteKit samples it right-side up.
    static func uprightTexture(from image: CGImage) -> SKTexture {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image, scale: 1, orientation: .up)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: rendered)
        prepareTextureForScaledDisplay(texture)
        return texture
    }

    /// Makes pixels whose RGB exactly matches `key` transparent (no tolerance).
    static func applyChromaKey(
        to image: CGImage,
        key: (r: UInt8, g: UInt8, b: UInt8)
    ) -> CGImage {
        let width = image.width
        let height = image.height
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
            return image
        }

        // UIKit-style top-left draw into a Quartz bottom-left buffer.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let kr = key.r
        let kg = key.g
        let kb = key.b

        for i in stride(from: 0, to: data.count, by: bytesPerPixel) {
            if data[i] == kr, data[i + 1] == kg, data[i + 2] == kb {
                data[i] = 0
                data[i + 1] = 0
                data[i + 2] = 0
                data[i + 3] = 0
            }
        }

        return context.makeImage() ?? image
    }

    static func parseHexRGB(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8)? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let intVal = UInt32(value, radix: 16) else { return nil }
        return (
            r: UInt8((intVal >> 16) & 0xFF),
            g: UInt8((intVal >> 8) & 0xFF),
            b: UInt8(intVal & 0xFF)
        )
    }

    /// Resolves sheet/atlas basenames under `root`, including per-animation subfolders.
    private static func resourceURL(
        named name: String,
        extensions: [String],
        root: String,
        bundle: Bundle
    ) throws -> URL {
        let folderHint = animationFolderName(from: name)
        var subdirectories = [
            root,
            "\(root)/\(folderHint)",
            folderHint,
            "",
        ]
        var seen = Set<String>()
        subdirectories = subdirectories.filter { seen.insert($0).inserted }

        for ext in extensions {
            for subdirectory in subdirectories {
                if subdirectory.isEmpty {
                    if let url = bundle.url(forResource: name, withExtension: ext) {
                        return url
                    }
                } else if let url = bundle.url(
                    forResource: name,
                    withExtension: ext,
                    subdirectory: subdirectory
                ) {
                    return url
                }
            }
        }
        throw SpriteLoadError.missingResource("\(root)/\(name)")
    }

    private static func animationFolderName(from resourceName: String) -> String {
        let suffixes = ["-spritesheet", "-atlas"]
        for suffix in suffixes where resourceName.hasSuffix(suffix) {
            return String(resourceName.dropLast(suffix.count))
        }
        return resourceName
    }
}

enum SpriteLoadError: Error, Equatable {
    case missingResource(String)
    case invalidImage(String)
    case noFrames(String)
}
