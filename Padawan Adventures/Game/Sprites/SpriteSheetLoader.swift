import CoreGraphics
import Foundation
import SpriteKit
import UIKit

enum SpriteSheetLoader {
    /// Loads a spritesheet + atlas and returns animation frames.
    ///
    /// Baked art is the norm: the bakers already applied chroma keying, trim and
    /// `flipAroundXAxis`, so those steps are skipped. Pass `isBaked: false` for the
    /// handful of raw sheets loaded straight from source, which still need that pixel
    /// processing at runtime.
    static func loadAnimation(
        sheet: String,
        atlas: String,
        root: String,
        chromaKey: String?,
        chromaKeyTolerance: UInt8 = 0,
        chromaKeyFeather: UInt8 = 0,
        chromaKeySmooth: Int = 0,
        bundle: Bundle = .main,
        trim: Bool = true,
        isBaked: Bool = true
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

        // Baked sheets are already keyed/trimmed/SK-oriented; skip pixel processing.
        let keyedImage: CGImage
        if isBaked {
            keyedImage = cgImage
        } else if let chromaKey, let rgb = parseHexRGB(chromaKey) {
            keyedImage = applyChromaKey(
                to: cgImage,
                key: rgb,
                tolerance: chromaKeyTolerance,
                feather: chromaKeyFeather,
                smoothRadius: chromaKeySmooth
            )
        } else {
            keyedImage = cgImage
        }

        let sheetWidth = keyedImage.width
        let sheetHeight = keyedImage.height
        guard sheetWidth > 0, sheetHeight > 0 else {
            throw SpriteLoadError.invalidImage(sheet)
        }

        let allOrdered = atlasDoc.orderedFrames
        guard !allOrdered.isEmpty else {
            throw SpriteLoadError.noFrames(atlas)
        }
        let allDurations = atlasDoc.frameDurationsSeconds(ordered: allOrdered.map(\.frame))
        let loopRange = atlasDoc.loopFrameRange(count: allOrdered.count)
        let ordered = Array(allOrdered[loopRange])
        let durations = Array(allDurations[loopRange])

        // Runtime trim needs per-frame CGImage crops. Otherwise share one parent texture
        // and slice frames with normalized SKTexture(rect:in:) sub-rects.
        let appliesRuntimeTrim = !isBaked && trim
        if !appliesRuntimeTrim {
            return try loadAnimationFromParentSubrects(
                keyedImage: keyedImage,
                sheetWidth: sheetWidth,
                sheetHeight: sheetHeight,
                ordered: ordered,
                durations: durations,
                atlas: atlas,
                applySpriteKitPrepFlip: !isBaked
            )
        }

        var croppedFrames: [CGImage] = []
        croppedFrames.reserveCapacity(ordered.count)

        for entry in ordered {
            let rect = entry.frame
            // Exact atlas pixel rect first (row-major order preserved).
            let crop = CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)
            guard crop.minX >= 0, crop.minY >= 0,
                  crop.maxX <= CGFloat(sheetWidth) + 0.5,
                  crop.maxY <= CGFloat(sheetHeight) + 0.5,
                  let cropped = keyedImage.cropping(to: crop) else {
                throw SpriteLoadError.frameOutOfBounds(
                    atlas: atlas,
                    frame: entry.key,
                    rect: "(\(rect.x),\(rect.y),\(rect.w),\(rect.h))"
                )
            }
            croppedFrames.append(cropped)
        }

        // Shared opaque trim: feet sit on the texture edge (anchor) and fitHeight
        // sizes the character, not the padded 256×256 atlas cell.
        let trimmedFrames = trimToSharedOpaqueBounds(croppedFrames)

        var frames: [SpriteFrame] = []
        frames.reserveCapacity(trimmedFrames.count)
        for (index, image) in trimmedFrames.enumerated() {
            // Source path: flip around X for SpriteKit after chroma/trim.
            let displayImage = flipAroundXAxis(image)
            frames.append(
                SpriteFrame(
                    texture: makeFrameTexture(from: displayImage),
                    duration: max(durations[index], 0.000_001)
                )
            )
        }
        return SpriteAnimation(frames: frames)
    }

    /// One parent `SKTexture` plus normalized sub-rects (SpriteKit origin is bottom-left).
    ///
    /// When `applySpriteKitPrepFlip` is true (unbaked, no trim), the sheet is X-flipped once
    /// so frame pixels match the trim-path prep that `AnimatedSpriteNode` undoes with yScale=-1.
    /// Baked sheets are already SK-oriented, so flip is skipped and atlas rects map directly.
    private static func loadAnimationFromParentSubrects(
        keyedImage: CGImage,
        sheetWidth: Int,
        sheetHeight: Int,
        ordered: [(key: String, frame: SpriteAtlas.SpriteAtlasFrame)],
        durations: [TimeInterval],
        atlas: String,
        applySpriteKitPrepFlip: Bool
    ) throws -> SpriteAnimation {
        let parentImage = applySpriteKitPrepFlip ? flipAroundXAxis(keyedImage) : keyedImage
        let parent = SKTexture(image: UIImage(cgImage: parentImage, scale: 1, orientation: .up))
        prepareTextureForScaledDisplay(parent)

        var frames: [SpriteFrame] = []
        frames.reserveCapacity(ordered.count)
        for (index, entry) in ordered.enumerated() {
            let rect = entry.frame
            let x = rect.x
            let y = rect.y
            let w = rect.w
            let h = rect.h
            guard x >= 0, y >= 0, w > 0, h > 0,
                  x + w <= sheetWidth,
                  y + h <= sheetHeight else {
                throw SpriteLoadError.frameOutOfBounds(
                    atlas: atlas,
                    frame: entry.key,
                    rect: "(\(x),\(y),\(w),\(h))"
                )
            }
            // Atlas y is top-left. After optional X-flip, top-left y becomes sheetH - y - h.
            let topLeftY = applySpriteKitPrepFlip ? (sheetHeight - y - h) : y
            let frameTex = makeSubrectTexture(
                x: x,
                y: topLeftY,
                w: w,
                h: h,
                sheetWidth: sheetWidth,
                sheetHeight: sheetHeight,
                parent: parent
            )
            frames.append(
                SpriteFrame(
                    texture: frameTex,
                    duration: max(durations[index], 0.000_001)
                )
            )
        }
        return SpriteAnimation(frames: frames)
    }

    nonisolated static func resourceURL(
        named name: String,
        extensions: [String],
        root: String,
        bundle: Bundle
    ) throws -> URL {
        for ext in extensions {
            let url = root.isEmpty
                ? bundle.url(forResource: name, withExtension: ext)
                : bundle.url(forResource: name, withExtension: ext, subdirectory: root)
            if let url { return url }
        }
        throw SpriteLoadError.missingResource("\(root)/\(name)")
    }
}

enum SpriteLoadError: Error, Equatable {
    case missingResource(String)
    case invalidImage(String)
    case noFrames(String)
    case frameOutOfBounds(atlas: String, frame: String, rect: String)
}
