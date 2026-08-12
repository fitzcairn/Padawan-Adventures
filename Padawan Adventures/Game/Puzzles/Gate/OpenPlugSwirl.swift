import SpriteKit
import UIKit

/// Looping gold particle swirl drawn around an empty word-plug socket while the
/// player is dragging a letter, so drop targets stay easy to spot.
@MainActor
enum OpenPlugSwirl {
    static let nodeName = "openPlugSwirl"
    static let motionKey = "openPlugSwirlMotion"
    static let cleanupKey = "openPlugSwirlCleanup"
    static let goldEmitterName = "openPlugGold"
    static let goldHotEmitterName = "openPlugGoldHot"

    static let revolutionDuration: TimeInterval = 0.8
    static let particleLifetime: TimeInterval = 0.4
    static let birthRate: CGFloat = 56
    /// Orbit radius as a fraction of the socket's longest side.
    static let orbitRadiusFraction: CGFloat = 0.42

    static let gold = UIColor(red: 1, green: 0.84, blue: 0.35, alpha: 1)
    static let goldHot = UIColor(red: 1, green: 0.95, blue: 0.65, alpha: 1)

    static func attach(to parent: SKNode, radius: CGFloat, referenceHeight: CGFloat) {
        parent.removeAction(forKey: cleanupKey)
        parent.childNode(withName: nodeName)?.removeFromParent()

        let wrapper = SKNode()
        wrapper.name = nodeName
        wrapper.zPosition = 5
        wrapper.isUserInteractionEnabled = false
        parent.addChild(wrapper)

        let goldEmitter = makeEmitter(color: gold, name: goldEmitterName, referenceHeight: referenceHeight)
        let hotEmitter = makeEmitter(color: goldHot, name: goldHotEmitterName, referenceHeight: referenceHeight)
        goldEmitter.targetNode = wrapper
        hotEmitter.targetNode = wrapper
        goldEmitter.position = CGPoint(x: radius, y: 0)
        hotEmitter.position = CGPoint(x: -radius, y: 0)
        wrapper.addChild(goldEmitter)
        wrapper.addChild(hotEmitter)

        let motion = SKAction.customAction(withDuration: revolutionDuration) { _, elapsed in
            let t = CGFloat(elapsed / revolutionDuration)
            let angle = t * .pi * 2
            goldEmitter.position = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            hotEmitter.position = CGPoint(
                x: radius * cos(angle + .pi),
                y: radius * sin(angle + .pi)
            )
            goldEmitter.emissionAngle = angle + .pi / 2
            hotEmitter.emissionAngle = angle + .pi / 2 + .pi
        }
        wrapper.run(.repeatForever(motion), withKey: motionKey)
    }

    /// Stops spawning so the ring fades out, then removes the node.
    static func detach(from parent: SKNode) {
        parent.removeAction(forKey: cleanupKey)
        guard let node = parent.childNode(withName: nodeName) else { return }
        node.removeAction(forKey: motionKey)
        for case let emitter as SKEmitterNode in node.children {
            emitter.particleBirthRate = 0
        }
        parent.run(
            .sequence([
                .wait(forDuration: particleLifetime),
                .run { node.removeFromParent() },
            ]),
            withKey: cleanupKey
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
        let diameter = max(referenceHeight * 0.08, 3)
        emitter.particleSize = CGSize(width: diameter, height: diameter)
        emitter.particleAlpha = 0.95
        emitter.particleAlphaSpeed = -0.95 / CGFloat(particleLifetime)
        emitter.particleScale = 1
        emitter.particleScaleRange = 0.35
        emitter.particleScaleSpeed = -1.2
        let spread = referenceHeight * 0.08
        emitter.particlePositionRange = CGVector(dx: spread, dy: spread * 0.7)
        emitter.particleSpeed = referenceHeight * 0.08
        emitter.particleSpeedRange = referenceHeight * 0.04
        emitter.emissionAngleRange = .pi * 0.55
        emitter.particleRotationRange = .pi * 2
        emitter.particleRotationSpeed = 2.2
        return emitter
    }
}
