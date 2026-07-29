import UIKit

/// Shared gold celebration burst (level-select unlocks, HUD score count-up).
@MainActor
enum GoldSparkleEmitter {
    private static var cachedParticle: CGImage?

    static func makeLayer(side: CGFloat, position: CGPoint) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .circle
        emitter.emitterMode = .outline
        emitter.renderMode = .additive
        emitter.emitterSize = CGSize(width: side * 0.92, height: side * 0.92)
        emitter.emitterPosition = position
        emitter.zPosition = 1

        let cell = CAEmitterCell()
        cell.contents = particleImage()
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
        return emitter
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
