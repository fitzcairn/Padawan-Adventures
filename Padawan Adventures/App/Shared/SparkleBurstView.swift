import SwiftUI
import UIKit

/// One-shot gold sparkle burst for SwiftUI celebration moments (inventory / planet unlock).
struct SparkleBurstView: UIViewRepresentable {
    var isActive: Bool
    /// Emitter diameter in points; particles scale with this.
    var diameter: CGFloat

    func makeUIView(context: Context) -> SparkleHostView {
        let view = SparkleHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: SparkleHostView, context: Context) {
        uiView.preferredDiameter = diameter
        if isActive {
            uiView.startIfNeeded()
        } else {
            uiView.stop(immediate: false)
        }
    }

    static func dismantleUIView(_ uiView: SparkleHostView, coordinator: ()) {
        uiView.stop(immediate: true)
    }
}

final class SparkleHostView: UIView {
    var preferredDiameter: CGFloat = 52

    private var sparkleLayer: CAEmitterLayer?
    private var sparkleStopWorkItem: DispatchWorkItem?
    private var emitEndWorkItem: DispatchWorkItem?
    private var isEmitting = false

    private static let emitSeconds: TimeInterval = 0.7
    private static let fadeOutSeconds: TimeInterval = 0.8

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let sparkleLayer else { return }
        sparkleLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        let side = max(bounds.width, preferredDiameter)
        sparkleLayer.emitterSize = CGSize(width: side * 0.92, height: side * 0.92)
    }

    func startIfNeeded() {
        guard !isEmitting else { return }
        removeEmitter(immediate: true)
        isEmitting = true
        layoutIfNeeded()

        let side = max(bounds.width, preferredDiameter, 24)
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .circle
        emitter.emitterMode = .outline
        emitter.renderMode = .additive
        emitter.emitterSize = CGSize(width: side * 0.92, height: side * 0.92)
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitter.zPosition = 1

        let cell = CAEmitterCell()
        cell.contents = Self.sparkleParticleImage().cgImage
        cell.birthRate = 36
        cell.lifetime = 0.7
        cell.lifetimeRange = 0.25
        cell.velocity = side * 0.55
        cell.velocityRange = side * 0.25
        cell.emissionRange = .pi * 2
        cell.scale = 0.22
        cell.scaleRange = 0.12
        cell.scaleSpeed = -0.2
        cell.alphaSpeed = -1.2
        cell.color = UIColor(red: 1, green: 0.84, blue: 0.35, alpha: 0.95).cgColor
        cell.alphaRange = 0.25
        cell.spin = 2
        cell.spinRange = 4

        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
        sparkleLayer = emitter

        let end = DispatchWorkItem { [weak self] in
            self?.stop(immediate: false)
        }
        emitEndWorkItem = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.emitSeconds, execute: end)
    }

    func stop(immediate: Bool) {
        emitEndWorkItem?.cancel()
        emitEndWorkItem = nil
        isEmitting = false
        guard let emitter = sparkleLayer else { return }
        emitter.birthRate = 0
        if immediate {
            removeEmitter(immediate: true)
            return
        }
        sparkleStopWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak emitter] in
            emitter?.removeFromSuperlayer()
            if self?.sparkleLayer === emitter {
                self?.sparkleLayer = nil
            }
        }
        sparkleStopWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOutSeconds, execute: work)
    }

    private func removeEmitter(immediate: Bool) {
        emitEndWorkItem?.cancel()
        emitEndWorkItem = nil
        sparkleStopWorkItem?.cancel()
        sparkleStopWorkItem = nil
        if immediate {
            sparkleLayer?.removeFromSuperlayer()
            sparkleLayer = nil
        }
        isEmitting = false
    }

    private static func sparkleParticleImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { context in
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
    }
}
