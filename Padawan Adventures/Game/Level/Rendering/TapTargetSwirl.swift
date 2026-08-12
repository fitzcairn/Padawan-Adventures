import SpriteKit
import UIKit

/// One-shot green/blue particle swirl that marks a tap-to-move floor target.
///
/// Starts on the floor diamond (same z as the tile, slightly above the art so it
/// is never hidden under it) and spirals upward to 20% of the player sprite's
/// height over 1s while fading out.
@MainActor
enum TapTargetSwirl {
    static let nodeName = "tapTargetSwirl"
    static let duration: TimeInterval = 1.0
    /// Visual rise as a fraction of the player sprite's display height.
    static let riseHeightFraction: CGFloat = 0.2
    /// Painter-order rise as a fraction of the floor→player z gap.
    static let zProgressFraction: CGFloat = 0.2
    /// Above floor tile sprites (`0.02`) so the first frame overlays the diamond.
    static let floorOverlayZ: CGFloat = 0.05
    static let orbitTurns: CGFloat = 2.5
    /// Orbit size as a fraction of the floor diamond.
    static let orbitRadiusFraction: CGFloat = 0.38
    /// Multiplier on `orbitRadiusFraction` at t = 0 (50% smaller than the original orbit).
    static let startRadiusScale: CGFloat = 0.5
    /// Multiplier on `orbitRadiusFraction` at t = 1 (10% smaller than the original orbit).
    static let endRadiusScale: CGFloat = 0.9
    static let particleLifetime: TimeInterval = 0.5
    static let birthRate: CGFloat = 84

    static let green = UIColor(red: 0.20, green: 0.84, blue: 0.29, alpha: 1)
    static let blue = UIColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1)

    static func riseDistance(playerSpriteHeight: CGFloat) -> CGFloat {
        playerSpriteHeight * riseHeightFraction
    }

    /// Orbit scale at `progress` (0 = start radius, 1 = end radius).
    static func orbitScale(progress: CGFloat) -> CGFloat {
        startRadiusScale + progress * (endRadiusScale - startRadiusScale)
    }

    /// zPosition at `progress` (0 = floor overlay, 1 = player sprite).
    static func zPosition(startZ: CGFloat, playerZ: CGFloat, progress: CGFloat) -> CGFloat {
        startZ + progress * (playerZ - startZ)
    }

    static func play(
        in parent: SKNode,
        at position: CGPoint,
        startZ: CGFloat,
        playerZ: CGFloat,
        tileWidth: CGFloat,
        tileHeight: CGFloat,
        playerSpriteHeight: CGFloat
    ) {
        let container = SKNode()
        container.name = nodeName
        container.position = position
        container.zPosition = startZ
        parent.addChild(container)

        let rise = riseDistance(playerSpriteHeight: playerSpriteHeight)
        let endZ = zPosition(startZ: startZ, playerZ: playerZ, progress: zProgressFraction)
        let baseRadiusX = tileWidth * orbitRadiusFraction
        let baseRadiusY = tileHeight * orbitRadiusFraction
        let startScale = startRadiusScale

        let greenEmitter = makeEmitter(color: green, name: "tapTargetGreen", referenceHeight: playerSpriteHeight)
        let blueEmitter = makeEmitter(color: blue, name: "tapTargetBlue", referenceHeight: playerSpriteHeight)
        // Leave particles in the container so they trail along the orbit instead of
        // clumping on the two emitter points.
        greenEmitter.targetNode = container
        blueEmitter.targetNode = container
        greenEmitter.position = CGPoint(x: baseRadiusX * startScale, y: 0)
        blueEmitter.position = CGPoint(x: -baseRadiusX * startScale, y: 0)
        container.addChild(greenEmitter)
        container.addChild(blueEmitter)

        let motion = SKAction.customAction(withDuration: duration) { node, elapsed in
            let t = CGFloat(elapsed / duration)
            let eased = 1 - (1 - t) * (1 - t)
            let angle = t * orbitTurns * (.pi * 2)
            let scale = orbitScale(progress: eased)
            let radiusX = baseRadiusX * scale
            let radiusY = baseRadiusY * scale
            greenEmitter.position = CGPoint(x: radiusX * cos(angle), y: radiusY * sin(angle))
            blueEmitter.position = CGPoint(
                x: radiusX * cos(angle + .pi),
                y: radiusY * sin(angle + .pi)
            )
            // Spray along the tangent so new particles fill the gap behind the orbit.
            greenEmitter.emissionAngle = angle + .pi / 2
            blueEmitter.emissionAngle = angle + .pi / 2 + .pi
            node.position = CGPoint(x: position.x, y: position.y + rise * eased)
            node.zPosition = startZ + (endZ - startZ) * eased
            let fade = max(1 - t, 0)
            greenEmitter.particleBirthRate = birthRate * fade
            blueEmitter.particleBirthRate = birthRate * fade
        }

        container.run(
            .sequence([
                motion,
                .wait(forDuration: particleLifetime),
                .removeFromParent(),
            ]),
            withKey: nodeName
        )
    }

    static func makeEmitter(color: UIColor, name: String, referenceHeight: CGFloat) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.name = name
        emitter.particleTexture = SparkleEmitterFactory.particleTexture()
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 1
        emitter.particleBlendMode = .add
        emitter.particleBirthRate = birthRate
        emitter.particleLifetime = CGFloat(particleLifetime)
        emitter.particleLifetimeRange = CGFloat(particleLifetime) * 0.3
        let diameter = max(referenceHeight * 0.07, 4)
        emitter.particleSize = CGSize(width: diameter, height: diameter)
        emitter.particleAlpha = 0.95
        emitter.particleAlphaSpeed = -0.95 / CGFloat(particleLifetime)
        emitter.particleScale = 1
        emitter.particleScaleRange = 0.4
        emitter.particleScaleSpeed = -1.4
        let spread = referenceHeight * 0.14
        emitter.particlePositionRange = CGVector(dx: spread, dy: spread * 0.7)
        emitter.particleSpeed = referenceHeight * 0.14
        emitter.particleSpeedRange = referenceHeight * 0.08
        emitter.emissionAngleRange = .pi * 0.9
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = 2.4
        return emitter
    }
}
