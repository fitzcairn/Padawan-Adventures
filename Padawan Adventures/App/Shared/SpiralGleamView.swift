import SwiftUI
import UIKit

/// Periodic rotating star twinkle on a sprite's upper-rightmost opaque pixel.
struct SpiralGleamView: UIViewRepresentable {
    /// When false, cancels the schedule and tears down any in-flight twinkle.
    var isEnabled: Bool
    /// Icon frame side in points (matches the inventory `scaledToFit` box).
    var diameter: CGFloat
    /// Treasure art as shown in the rack (before the 90° layout rotation).
    var image: UIImage?

    func makeUIView(context: Context) -> SpiralGleamHostView {
        let view = SpiralGleamHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: SpiralGleamHostView, context: Context) {
        uiView.preferredDiameter = diameter
        uiView.spriteImage = image
        uiView.setEnabled(isEnabled)
    }

    static func dismantleUIView(_ uiView: SpiralGleamHostView, coordinator: ()) {
        uiView.setEnabled(false)
    }
}

final class SpiralGleamHostView: UIView {
    var preferredDiameter: CGFloat = 52
    var spriteImage: UIImage? {
        didSet {
            if spriteImage !== oldValue {
                cachedHotspot = nil
            }
        }
    }

    private var scheduleWorkItem: DispatchWorkItem?
    private var cleanupWorkItem: DispatchWorkItem?
    private var twinkleLayer: CALayer?
    private var cachedHotspot: CGPoint?
    private var isEnabled = false
    private var isPlaying = false

    /// Mean seconds between twinkles.
    private static let meanInterval: TimeInterval = 5
    /// Wait spread around the mean (`3…7` with the default mean).
    private static let intervalHalfRange: TimeInterval = 2
    private static let twinkleDuration: TimeInterval = 0.7
    private static let alphaThreshold: UInt8 = 16

    private static var cachedStar: CGImage?

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            scheduleNext(initial: true)
        } else {
            cancelSchedule()
            stopTwinkle(immediate: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cachedHotspot = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelSchedule()
            stopTwinkle(immediate: true)
        } else if isEnabled, scheduleWorkItem == nil, !isPlaying {
            scheduleNext(initial: true)
        }
    }

    private func scheduleNext(initial: Bool) {
        cancelSchedule()
        guard isEnabled else { return }
        let delay: TimeInterval
        if initial {
            delay = TimeInterval.random(in: 0.4...Self.meanInterval)
        } else {
            let lo = Self.meanInterval - Self.intervalHalfRange
            let hi = Self.meanInterval + Self.intervalHalfRange
            delay = TimeInterval.random(in: lo...hi)
        }
        let work = DispatchWorkItem { [weak self] in
            self?.playTwinkle()
            self?.scheduleNext(initial: false)
        }
        scheduleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelSchedule() {
        scheduleWorkItem?.cancel()
        scheduleWorkItem = nil
    }

    private func playTwinkle() {
        guard isEnabled, !isPlaying, bounds.width > 0, bounds.height > 0 else { return }
        layoutIfNeeded()
        guard let hotspot = hotspotInView() else { return }

        isPlaying = true
        let side = max(preferredDiameter * 0.55, 22)

        // Outer layer owns opacity/scale; inner owns rotation so transforms don't clash.
        let host = CALayer()
        host.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        host.position = hotspot
        host.opacity = 0
        host.zPosition = 1

        let star = CALayer()
        star.contents = Self.starImage()
        star.contentsGravity = .resize
        star.frame = host.bounds
        // Additive so it reads as a bright glint on the art.
        star.compositingFilter = "plusL"
        host.addSublayer(star)
        layer.addSublayer(host)
        twinkleLayer = host

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.2, 0.55, 1]
        fade.duration = Self.twinkleDuration

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.2, 1.15, 1, 0.35]
        scale.keyTimes = [0, 0.25, 0.55, 1]
        scale.duration = Self.twinkleDuration

        let hostGroup = CAAnimationGroup()
        hostGroup.animations = [fade, scale]
        hostGroup.duration = Self.twinkleDuration
        hostGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        host.add(hostGroup, forKey: "twinkle")

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = CGFloat.pi * 0.75
        spin.duration = Self.twinkleDuration
        spin.timingFunction = CAMediaTimingFunction(name: .easeOut)
        star.add(spin, forKey: "spin")

        cleanupWorkItem?.cancel()
        let cleanup = DispatchWorkItem { [weak self, weak host] in
            host?.removeFromSuperlayer()
            if self?.twinkleLayer === host {
                self?.twinkleLayer = nil
            }
            self?.isPlaying = false
        }
        cleanupWorkItem = cleanup
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.twinkleDuration,
            execute: cleanup
        )
    }

    private func stopTwinkle(immediate: Bool) {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        isPlaying = false
        guard let twinkle = twinkleLayer else { return }
        twinkle.removeAllAnimations()
        if immediate {
            twinkle.removeFromSuperlayer()
            twinkleLayer = nil
        }
    }

    /// Upper-rightmost opaque pixel of the *displayed* sprite (after aspect-fit
    /// and the rack's 90° clockwise layout rotation).
    private func hotspotInView() -> CGPoint? {
        if let cachedHotspot {
            return cachedHotspot
        }
        guard let image = spriteImage?.cgImage else { return nil }
        let point = Self.upperRightOpaqueHotspot(in: image, bounds: bounds)
        cachedHotspot = point
        return point
    }

    /// First non-clear pixel nearest the upper-right of the laid-out sprite.
    static func upperRightOpaqueHotspot(
        in image: CGImage,
        bounds: CGRect,
        alphaThreshold: UInt8 = 16
    ) -> CGPoint? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, bounds.width > 0, bounds.height > 0 else { return nil }

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
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let corner = CGPoint(x: bounds.maxX, y: bounds.minY)
        var bestPoint: CGPoint?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for y in 0..<height {
            for x in 0..<width {
                guard data[(y * width + x) * bytesPerPixel + 3] >= alphaThreshold else {
                    continue
                }
                let point = mapImagePixel(
                    CGPoint(x: x, y: y),
                    imageWidth: width,
                    imageHeight: height,
                    into: bounds
                )
                let dx = point.x - corner.x
                let dy = point.y - corner.y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    bestPoint = point
                }
            }
        }
        return bestPoint
    }

    /// Maps an image pixel through `scaledToFit` into `rect`, then 90° clockwise
    /// around the rect center — matching `InventoryRackView`'s layout.
    static func mapImagePixel(
        _ pixel: CGPoint,
        imageWidth: Int,
        imageHeight: Int,
        into rect: CGRect
    ) -> CGPoint {
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        guard imageSize.width > 0, imageSize.height > 0, rect.width > 0, rect.height > 0 else {
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let origin = CGPoint(
            x: rect.minX + (rect.width - drawSize.width) * 0.5,
            y: rect.minY + (rect.height - drawSize.height) * 0.5
        )
        let fit = CGPoint(
            x: origin.x + (pixel.x + 0.5) * scale,
            y: origin.y + (pixel.y + 0.5) * scale
        )
        // 90° CW with y-down: (dx, dy) → (-dy, dx)
        let dx = fit.x - rect.midX
        let dy = fit.y - rect.midY
        return CGPoint(x: rect.midX - dy, y: rect.midY + dx)
    }

    /// Four intersecting spokes (cross + diagonals) that taper to points.
    private static func starImage() -> CGImage {
        if let cachedStar {
            return cachedStar
        }
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Soft core glow behind the spokes.
            let glowColors = [
                UIColor.white.withAlphaComponent(0.95).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            if let glow = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: glowColors,
                locations: [0, 1]
            ) {
                cg.drawRadialGradient(
                    glow,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: size.width * 0.18,
                    options: []
                )
            }

            // Long cross + shorter diagonals.
            drawSpoke(
                in: cg,
                center: center,
                angle: 0,
                halfLength: size.width * 0.48,
                halfWidth: size.width * 0.055
            )
            drawSpoke(
                in: cg,
                center: center,
                angle: .pi / 2,
                halfLength: size.width * 0.48,
                halfWidth: size.width * 0.055
            )
            drawSpoke(
                in: cg,
                center: center,
                angle: .pi / 4,
                halfLength: size.width * 0.32,
                halfWidth: size.width * 0.035
            )
            drawSpoke(
                in: cg,
                center: center,
                angle: -.pi / 4,
                halfLength: size.width * 0.32,
                halfWidth: size.width * 0.035
            )
        }
        let cgImage = image.cgImage!
        cachedStar = cgImage
        return cgImage
    }

    /// Diamond-shaped spoke centered on `center`, pointed at both ends.
    private static func drawSpoke(
        in cg: CGContext,
        center: CGPoint,
        angle: CGFloat,
        halfLength: CGFloat,
        halfWidth: CGFloat
    ) {
        let cosA = cos(angle)
        let sinA = sin(angle)
        let along = CGPoint(x: cosA, y: sinA)
        let across = CGPoint(x: -sinA, y: cosA)

        let tipA = CGPoint(
            x: center.x + along.x * halfLength,
            y: center.y + along.y * halfLength
        )
        let tipB = CGPoint(
            x: center.x - along.x * halfLength,
            y: center.y - along.y * halfLength
        )
        let sideA = CGPoint(
            x: center.x + across.x * halfWidth,
            y: center.y + across.y * halfWidth
        )
        let sideB = CGPoint(
            x: center.x - across.x * halfWidth,
            y: center.y - across.y * halfWidth
        )

        cg.saveGState()
        cg.beginPath()
        cg.move(to: tipA)
        cg.addLine(to: sideA)
        cg.addLine(to: tipB)
        cg.addLine(to: sideB)
        cg.closePath()
        cg.clip()

        let colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.5, 1]
        ) {
            cg.drawLinearGradient(
                gradient,
                start: tipA,
                end: tipB,
                options: []
            )
        }
        cg.restoreGState()
    }
}
