import CoreGraphics
import Foundation
import SpriteKit
import UIKit

extension SpriteSheetLoader {
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
}
