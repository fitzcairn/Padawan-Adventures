import CoreGraphics
import Foundation
import SpriteKit
import UIKit

extension SpriteSheetLoader {
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
}
