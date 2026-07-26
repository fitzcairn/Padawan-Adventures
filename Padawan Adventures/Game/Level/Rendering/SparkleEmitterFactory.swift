import SpriteKit
import UIKit

/// Builds the decorative particle halo drawn behind highlighted sprites.
@MainActor
enum SparkleEmitterFactory {
    static let nodeName = "sparkleHighlight"

    /// Soft radial dot, drawn once and shared by every emitter.
    private static var cachedTexture: SKTexture?

    /// White radial gradient so `particleColorBlendFactor = 1` can tint to any colour.
    static func particleTexture() -> SKTexture {
        if let cachedTexture {
            return cachedTexture
        }
        let size = CGSize(width: 32, height: 32)
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
        let texture = SKTexture(image: image)
        cachedTexture = texture
        return texture
    }

    /// - Parameters:
    ///   - referenceHeight: display height of the sprite the halo sits behind;
    ///     every size in `config` is a fraction of this.
    static func makeNode(config: HighlightConfig, referenceHeight: CGFloat) -> SKEmitterNode {
        let emitter = configuredEmitter(config: config, referenceHeight: referenceHeight)
        // Prefill so the halo is visible on the first frame.
        emitter.advanceSimulationTime(config.lifetime)
        return emitter
    }

    /// One-shot radial explode (projectile / impact). Removes itself after particles die.
    static func makeBurstNode(
        config: HighlightConfig,
        referenceHeight: CGFloat,
        particleCount: Int = 40
    ) -> SKEmitterNode {
        let count = max(particleCount, 1)
        let emitter = configuredEmitter(config: config, referenceHeight: referenceHeight)
        emitter.numParticlesToEmit = count
        // Dump the whole burst in a short window so it reads as an explode.
        emitter.particleBirthRate = CGFloat(count) / 0.06
        emitter.particlePositionRange = CGVector(
            dx: referenceHeight * CGFloat(config.radius) * 0.35,
            dy: referenceHeight * CGFloat(config.radius) * 0.25
        )
        emitter.particleSpeed = referenceHeight * 0.95
        emitter.particleSpeedRange = referenceHeight * 0.45
        emitter.yAcceleration = -referenceHeight * 0.35
        return emitter
    }

    private static func configuredEmitter(
        config: HighlightConfig,
        referenceHeight: CGFloat
    ) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.name = nodeName
        emitter.zPosition = 0
        emitter.particleTexture = particleTexture()
        emitter.particleColor = config.uiColor
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.particleBirthRate = CGFloat(config.birthRate)
        emitter.particleLifetime = CGFloat(config.lifetime)
        emitter.particleLifetimeRange = emitter.particleLifetime * 0.5
        let spread = referenceHeight * CGFloat(config.radius) * 2
        emitter.particlePositionRange = CGVector(dx: spread, dy: spread * 0.6)
        let diameter = referenceHeight * CGFloat(config.particleSize)
        emitter.particleSize = CGSize(width: diameter, height: diameter)
        emitter.particleAlpha = CGFloat(config.alpha)
        emitter.particleAlphaSpeed = -CGFloat(config.alpha) / CGFloat(config.lifetime)
        emitter.particleScale = 1
        emitter.particleScaleRange = 0.5
        emitter.particleScaleSpeed = -0.4
        emitter.particleSpeed = referenceHeight * 0.15
        emitter.particleSpeedRange = referenceHeight * 0.1
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 2
        emitter.yAcceleration = referenceHeight * 0.2
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = 1
        return emitter
    }

    /// Stops new particles without cutting off the ones already alive.
    static func stop(in container: SKNode) {
        for case let emitter as SKEmitterNode in container.children
        where emitter.name == nodeName {
            emitter.particleBirthRate = 0
        }
    }
}
