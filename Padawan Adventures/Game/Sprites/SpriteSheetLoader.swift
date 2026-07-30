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

        let ordered = atlasDoc.orderedFrames
        guard !ordered.isEmpty else {
            throw SpriteLoadError.noFrames(atlas)
        }
        let durations = atlasDoc.frameDurationsSeconds(ordered: ordered.map(\.frame))

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

    /// Mirrors the image around the X axis (top ↔ bottom). Applied after load/trim only.
    static func flipAroundXAxis(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

        let bytesPerRow = width * 4
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

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Mirrors the image around the Y axis (left ↔ right).
    static func flipAroundYAxis(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

        let bytesPerRow = width * 4
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

        context.translateBy(x: CGFloat(width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Keeps only the primary opaque connected component (4-connected), clearing the rest.
    ///
    /// Prefers the component whose centroid is nearest the image center so a crop that
    /// accidentally includes a neighbor tip does not steal the frame.
    /// Uses an identity draw so top-left origin matches atlas crop space.
    static func keepPrimaryOpaqueComponent(
        _ image: CGImage,
        alphaThreshold: UInt8 = 1
    ) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return image }

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

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var labels = [Int](repeating: 0, count: width * height)
        var nextLabel = 1
        var centroids: [(sumX: Int, sumY: Int, count: Int)] = [(0, 0, 0)] // 1-indexed
        let centerX = width / 2
        let centerY = height / 2

        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if data[i * bytesPerPixel + 3] < alphaThreshold || labels[i] != 0 { continue }
                var queue = [i]
                labels[i] = nextLabel
                var head = 0
                var sumX = 0
                var sumY = 0
                var count = 0
                while head < queue.count {
                    let ci = queue[head]
                    head += 1
                    let cx = ci % width
                    let cy = ci / width
                    sumX += cx
                    sumY += cy
                    count += 1
                    if cx > 0 {
                        let ni = ci - 1
                        if data[ni * bytesPerPixel + 3] >= alphaThreshold, labels[ni] == 0 {
                            labels[ni] = nextLabel
                            queue.append(ni)
                        }
                    }
                    if cx < width - 1 {
                        let ni = ci + 1
                        if data[ni * bytesPerPixel + 3] >= alphaThreshold, labels[ni] == 0 {
                            labels[ni] = nextLabel
                            queue.append(ni)
                        }
                    }
                    if cy > 0 {
                        let ni = ci - width
                        if data[ni * bytesPerPixel + 3] >= alphaThreshold, labels[ni] == 0 {
                            labels[ni] = nextLabel
                            queue.append(ni)
                        }
                    }
                    if cy < height - 1 {
                        let ni = ci + width
                        if data[ni * bytesPerPixel + 3] >= alphaThreshold, labels[ni] == 0 {
                            labels[ni] = nextLabel
                            queue.append(ni)
                        }
                    }
                }
                centroids.append((sumX, sumY, count))
                nextLabel += 1
            }
        }

        guard nextLabel > 1 else { return image }

        var bestLabel = 1
        var bestScore = Double.greatestFiniteMagnitude
        for label in 1..<nextLabel {
            let c = centroids[label]
            guard c.count > 0 else { continue }
            let cx = Double(c.sumX) / Double(c.count)
            let cy = Double(c.sumY) / Double(c.count)
            let dist = (cx - Double(centerX)) * (cx - Double(centerX))
                + (cy - Double(centerY)) * (cy - Double(centerY))
            // Slightly prefer larger components when distances are similar.
            let score = dist - Double(c.count) * 0.01
            if score < bestScore {
                bestScore = score
                bestLabel = label
            }
        }

        for i in 0..<(width * height) {
            if labels[i] != bestLabel {
                let o = i * bytesPerPixel
                data[o] = 0
                data[o + 1] = 0
                data[o + 2] = 0
                data[o + 3] = 0
            }
        }

        return context.makeImage() ?? image
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

    /// Makes pixels whose RGB matches `key` transparent, with optional soft edges.
    ///
    /// Distance is the max per-channel delta from `key`. Pixels within `tolerance`
    /// become fully transparent. Pixels between `tolerance` and `tolerance + feather`
    /// fade from transparent → opaque (smoothstep) so near-key fringe softens.
    /// When `smoothRadius` > 0, the alpha matte is then box-blurred and RGB is
    /// re-premultiplied so remaining edge steps blend instead of ringing white.
    ///
    /// Preserves the source image's top-left origin so atlas frame rects
    /// (`y: 0` = top row of the spritesheet) stay correct after keying.
    static func applyChromaKey(
        to image: CGImage,
        key: (r: UInt8, g: UInt8, b: UInt8),
        tolerance: UInt8 = 0,
        feather: UInt8 = 0,
        smoothRadius: Int = 0
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

        // Identity draw — do not Y-flip. A flip here made atlas (0,0) crop the
        // bottom row of the sheet while keys still looked "in order".
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let kr = Int(key.r)
        let kg = Int(key.g)
        let kb = Int(key.b)
        let hardTol = Int(tolerance)
        let featherWidth = Int(feather)
        let softTol = hardTol + featherWidth

        for i in stride(from: 0, to: data.count, by: bytesPerPixel) {
            let dr = abs(Int(data[i]) - kr)
            let dg = abs(Int(data[i + 1]) - kg)
            let db = abs(Int(data[i + 2]) - kb)
            let distance = max(dr, max(dg, db))

            if distance <= hardTol {
                data[i] = 0
                data[i + 1] = 0
                data[i + 2] = 0
                data[i + 3] = 0
                continue
            }

            guard featherWidth > 0, distance < softTol else { continue }

            // Smoothstep falloff — kills near-key fringe harder than a linear ramp.
            let t = Double(distance - hardTol) / Double(featherWidth)
            let keep = t * t * (3.0 - 2.0 * t)
            data[i] = UInt8(clamping: Int((Double(data[i]) * keep).rounded()))
            data[i + 1] = UInt8(clamping: Int((Double(data[i + 1]) * keep).rounded()))
            data[i + 2] = UInt8(clamping: Int((Double(data[i + 2]) * keep).rounded()))
            data[i + 3] = UInt8(clamping: Int((Double(data[i + 3]) * keep).rounded()))
        }

        if smoothRadius > 0 {
            smoothPremultipliedAlphaEdge(
                data: &data,
                width: width,
                height: height,
                radius: smoothRadius
            )
        }

        return context.makeImage() ?? image
    }

    /// Separable box-blur on alpha, then re-premultiply RGB so chroma edges don't stair-step.
    static func smoothPremultipliedAlphaEdge(
        data: inout [UInt8],
        width: Int,
        height: Int,
        radius: Int
    ) {
        guard radius > 0, width > 0, height > 0 else { return }
        let count = width * height
        var straightR = [UInt8](repeating: 0, count: count)
        var straightG = [UInt8](repeating: 0, count: count)
        var straightB = [UInt8](repeating: 0, count: count)
        var alpha = [UInt8](repeating: 0, count: count)

        for idx in 0..<count {
            let i = idx * 4
            let a = Int(data[i + 3])
            alpha[idx] = data[i + 3]
            if a > 0 {
                straightR[idx] = UInt8(clamping: (Int(data[i]) * 255 + a / 2) / a)
                straightG[idx] = UInt8(clamping: (Int(data[i + 1]) * 255 + a / 2) / a)
                straightB[idx] = UInt8(clamping: (Int(data[i + 2]) * 255 + a / 2) / a)
            }
        }

        var horizontal = [UInt8](repeating: 0, count: count)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var sum = 0
                var samples = 0
                let x0 = max(0, x - radius)
                let x1 = min(width - 1, x + radius)
                for xx in x0...x1 {
                    sum += Int(alpha[row + xx])
                    samples += 1
                }
                horizontal[row + x] = UInt8(clamping: (sum + samples / 2) / samples)
            }
        }

        var blurred = [UInt8](repeating: 0, count: count)
        for x in 0..<width {
            for y in 0..<height {
                var sum = 0
                var samples = 0
                let y0 = max(0, y - radius)
                let y1 = min(height - 1, y + radius)
                for yy in y0...y1 {
                    sum += Int(horizontal[yy * width + x])
                    samples += 1
                }
                blurred[y * width + x] = UInt8(clamping: (sum + samples / 2) / samples)
            }
        }

        for idx in 0..<count {
            let i = idx * 4
            let a = Int(blurred[idx])
            data[i + 3] = blurred[idx]
            if a == 0 {
                data[i] = 0
                data[i + 1] = 0
                data[i + 2] = 0
            } else {
                data[i] = UInt8(clamping: (Int(straightR[idx]) * a + 127) / 255)
                data[i + 1] = UInt8(clamping: (Int(straightG[idx]) * a + 127) / 255)
                data[i + 2] = UInt8(clamping: (Int(straightB[idx]) * a + 127) / 255)
            }
        }
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

    /// Resolves a sheet/atlas basename in exactly one bundle subdirectory.
    ///
    /// `Resources/` is flat — one folder per level, one per shared tree — so there is
    /// no search to do. An exact lookup means a missing file fails here instead of
    /// silently resolving to a same-named file belonging to another level.
    /// An empty `root` looks at the bundle root.
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
