import Foundation
import ImagePlayground
import UIKit

enum SillyFaceAvatarGenerator {
    private static let prompts = [
        "silly cartoon face with googly eyes and a huge grin",
        "goofy alien face sticking out its tongue",
        "cheerful robot face with mismatched eyes",
        "wacky monster face with a tiny hat",
        "funny potato face with a big smile",
        "playful clown face with bright colors",
    ]

    /// Generates a 200×200 JPEG silly-face avatar using on-device ImageCreator when available.
    static func generateJPEG(seedName: String) async -> Data {
        if let generated = await generateWithImageCreator(seedName: seedName) {
            return generated
        }
        return proceduralJPEG(seedName: seedName)
    }

    static func proceduralJPEG(seedName: String) -> Data {
        var rng = SeededGenerator(seed: stableSeed(for: seedName))
        let size = PlayerAvatarImage.thumbnailSize
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)

            let hue = CGFloat.random(in: 0...1, using: &rng)
            UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).setFill()
            cg.fill(bounds)

            let faceInset = size.width * 0.12
            let faceRect = bounds.insetBy(dx: faceInset, dy: faceInset)
            UIColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.35, brightness: 1, alpha: 1)
                .setFill()
            cg.fillEllipse(in: faceRect)

            let eyeY = faceRect.minY + faceRect.height * 0.35
            let eyeRadius = size.width * CGFloat.random(in: 0.06...0.1, using: &rng)
            let leftEye = CGPoint(x: faceRect.minX + faceRect.width * 0.32, y: eyeY)
            let rightEye = CGPoint(x: faceRect.minX + faceRect.width * 0.68, y: eyeY)
            UIColor.white.setFill()
            cg.fillEllipse(in: CGRect(x: leftEye.x - eyeRadius, y: leftEye.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
            cg.fillEllipse(in: CGRect(x: rightEye.x - eyeRadius, y: rightEye.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))

            let pupil = eyeRadius * 0.45
            UIColor.black.setFill()
            let pupilOffsetX = CGFloat.random(in: -eyeRadius * 0.25...eyeRadius * 0.25, using: &rng)
            let pupilOffsetY = CGFloat.random(in: -eyeRadius * 0.25...eyeRadius * 0.25, using: &rng)
            cg.fillEllipse(in: CGRect(
                x: leftEye.x - pupil + pupilOffsetX,
                y: leftEye.y - pupil + pupilOffsetY,
                width: pupil * 2,
                height: pupil * 2
            ))
            cg.fillEllipse(in: CGRect(
                x: rightEye.x - pupil - pupilOffsetX,
                y: rightEye.y - pupil + pupilOffsetY,
                width: pupil * 2,
                height: pupil * 2
            ))

            let smileY = faceRect.minY + faceRect.height * 0.62
            let smileWidth = faceRect.width * CGFloat.random(in: 0.35...0.55, using: &rng)
            let smileHeight = faceRect.height * CGFloat.random(in: 0.18...0.28, using: &rng)
            let smileRect = CGRect(
                x: faceRect.midX - smileWidth / 2,
                y: smileY,
                width: smileWidth,
                height: smileHeight
            )
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(size.width * 0.045)
            cg.setLineCap(.round)
            cg.addArc(
                center: CGPoint(x: smileRect.midX, y: smileRect.minY),
                radius: smileWidth / 2,
                startAngle: 0.15 * .pi,
                endAngle: 0.85 * .pi,
                clockwise: false
            )
            cg.strokePath()

            // Tiny nose
            let nose = CGRect(
                x: faceRect.midX - size.width * 0.03,
                y: faceRect.minY + faceRect.height * 0.48,
                width: size.width * 0.06,
                height: size.width * 0.06
            )
            UIColor(hue: hue, saturation: 0.5, brightness: 0.7, alpha: 1).setFill()
            cg.fillEllipse(in: nose)
        }

        return image.jpegData(compressionQuality: 0.85)
            ?? Data()
    }

    private nonisolated static func stableSeed(for name: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash == 0 ? 1 : hash
    }

    private static func generateWithImageCreator(seedName: String) async -> Data? {
        do {
            let creator = try await ImageCreator()
            let styles = creator.availableStyles
            guard !styles.isEmpty else { return nil }
            let style = styles.contains(.animation) ? ImagePlaygroundStyle.animation : styles[0]

            var rng = SeededGenerator(seed: stableSeed(for: seedName))
            let prompt = rng.pick(prompts) ?? prompts[0]

            let stream = creator.images(
                for: [.text(prompt)],
                style: style,
                limit: 1
            )
            for try await created in stream {
                let uiImage = UIImage(cgImage: created.cgImage)
                return PlayerAvatarImage.makeThumbnailJPEG(from: uiImage)
            }
            return nil
        } catch {
            return nil
        }
    }
}
