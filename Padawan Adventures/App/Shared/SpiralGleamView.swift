import SwiftUI
import UIKit

/// Periodic white spiral particle trail that orbits a SwiftUI icon (inventory rack).
struct SpiralGleamView: UIViewRepresentable {
    /// When false, cancels the schedule and tears down any in-flight gleam.
    var isEnabled: Bool
    /// Icon diameter in points; orbit radius and particle size scale with this.
    var diameter: CGFloat

    func makeUIView(context: Context) -> SpiralGleamHostView {
        let view = SpiralGleamHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: SpiralGleamHostView, context: Context) {
        uiView.preferredDiameter = diameter
        uiView.setEnabled(isEnabled)
    }

    static func dismantleUIView(_ uiView: SpiralGleamHostView, coordinator: ()) {
        uiView.setEnabled(false)
    }
}

final class SpiralGleamHostView: UIView {
    var preferredDiameter: CGFloat = 52

    private var scheduleWorkItem: DispatchWorkItem?
    private var cleanupWorkItem: DispatchWorkItem?
    private var gleamLayer: CAEmitterLayer?
    private var isEnabled = false
    private var isPlaying = false

    /// Mean seconds between gleam starts.
    private static let meanInterval: TimeInterval = 5
    /// Wait spread around the mean (`3…7` with the default mean).
    private static let intervalHalfRange: TimeInterval = 2
    private static let orbitDuration: TimeInterval = 0.9
    private static let particleLifetime: Float = 0.38

    private static var cachedParticle: CGImage?

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            scheduleNext(initial: true)
        } else {
            cancelSchedule()
            stopGleam(immediate: true)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelSchedule()
            stopGleam(immediate: true)
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
            self?.playGleam()
            self?.scheduleNext(initial: false)
        }
        scheduleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelSchedule() {
        scheduleWorkItem?.cancel()
        scheduleWorkItem = nil
    }

    private func playGleam() {
        guard isEnabled, !isPlaying, bounds.width > 0, bounds.height > 0 else { return }
        isPlaying = true
        layoutIfNeeded()

        let side = max(bounds.width, preferredDiameter, 24)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let startRadius = side * 0.32
        let endRadius = side * 0.52

        let emitter = CAEmitterLayer()
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.renderMode = .additive
        emitter.zPosition = 1
        emitter.emitterPosition = spiralPoint(
            center: center,
            radius: startRadius,
            endRadius: endRadius,
            t: 0
        )

        let cell = CAEmitterCell()
        cell.contents = Self.particleImage()
        cell.birthRate = 90
        cell.lifetime = Self.particleLifetime
        cell.lifetimeRange = 0.1
        cell.velocity = side * 0.12
        cell.velocityRange = side * 0.04
        cell.emissionRange = .pi * 0.35
        cell.scale = 0.18
        cell.scaleRange = 0.08
        cell.scaleSpeed = -0.35
        cell.alphaSpeed = -2.4
        cell.color = UIColor.white.withAlphaComponent(0.95).cgColor
        cell.spinRange = 4
        emitter.emitterCells = [cell]

        layer.addSublayer(emitter)
        gleamLayer = emitter

        let path = spiralPath(
            center: center,
            startRadius: startRadius,
            endRadius: endRadius
        )
        let orbit = CAKeyframeAnimation(keyPath: "emitterPosition")
        orbit.path = path
        orbit.duration = Self.orbitDuration
        orbit.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        orbit.calculationMode = .paced
        orbit.fillMode = .forwards
        orbit.isRemovedOnCompletion = false
        emitter.add(orbit, forKey: "spiralOrbit")

        cleanupWorkItem?.cancel()
        let cleanup = DispatchWorkItem { [weak self, weak emitter] in
            emitter?.birthRate = 0
            let remove = DispatchWorkItem { [weak self, weak emitter] in
                emitter?.removeFromSuperlayer()
                if self?.gleamLayer === emitter {
                    self?.gleamLayer = nil
                }
                self?.isPlaying = false
            }
            self?.cleanupWorkItem = remove
            DispatchQueue.main.asyncAfter(
                deadline: .now() + TimeInterval(Self.particleLifetime) + 0.15,
                execute: remove
            )
        }
        cleanupWorkItem = cleanup
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.orbitDuration,
            execute: cleanup
        )
    }

    private func stopGleam(immediate: Bool) {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        isPlaying = false
        guard let emitter = gleamLayer else { return }
        emitter.removeAllAnimations()
        emitter.birthRate = 0
        if immediate {
            emitter.removeFromSuperlayer()
            gleamLayer = nil
        }
    }

    private func spiralPath(
        center: CGPoint,
        startRadius: CGFloat,
        endRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        let steps = 64
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let point = spiralPoint(
                center: center,
                radius: startRadius,
                endRadius: endRadius,
                t: t
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func spiralPoint(
        center: CGPoint,
        radius startRadius: CGFloat,
        endRadius: CGFloat,
        t: CGFloat
    ) -> CGPoint {
        let angle = t * .pi * 2 - .pi / 2
        let r = startRadius + (endRadius - startRadius) * t
        return CGPoint(
            x: center.x + cos(angle) * r,
            y: center.y + sin(angle) * r
        )
    }

    private static func particleImage() -> CGImage {
        if let cachedParticle {
            return cachedParticle
        }
        let size = CGSize(width: 24, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else {
                return
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )
        }
        let cgImage = image.cgImage!
        cachedParticle = cgImage
        return cgImage
    }
}
