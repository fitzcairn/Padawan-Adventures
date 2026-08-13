import SpriteKit
import UIKit

extension PlaceholderFactory {
    static func startIdleBounce(on node: SKNode) {
        node.removeAction(forKey: "pickupBounce")
        let up = SKAction.moveBy(x: 0, y: pickupBounceAmplitude, duration: 0.45)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -pickupBounceAmplitude, duration: 0.45)
        down.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, down])), withKey: "pickupBounce")
    }

    /// One bounce then fade; calls `completion` when finished.
    static func playCollectAnimation(on node: SKNode, completion: @escaping () -> Void) {
        SparkleEmitterFactory.stop(in: node)
        let icon = node.children.first { !($0 is SKEmitterNode) } ?? node
        icon.removeAction(forKey: "pickupBounce")
        let up = SKAction.moveBy(x: 0, y: pickupBounceAmplitude, duration: 0.2)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -pickupBounceAmplitude, duration: 0.2)
        down.timingMode = .easeInEaseOut
        let fade = SKAction.fadeOut(withDuration: 0.25)
        node.run(.sequence([
            .run { icon.run(.sequence([up, down])) },
            .wait(forDuration: 0.4),
            fade,
            .run(completion),
        ]))
    }

    /// Duration for gate dissolve + connecting-floor fade-in after a successful puzzle.
    /// Nonisolated so it can be used as a default argument (those are always nonisolated).
    nonisolated static let gateOpenDuration: TimeInterval = 2.0

    /// Gate sprite fades out with sparkles while `revealNodes` — the connecting floor tiles
    /// and whatever art the opened gate uncovers — fade in over the same window.
    ///
    /// Particles do not inherit parent alpha, so gate visuals fade separately from the
    /// emitter. Calls `completion` after the dissolve finishes (and lingering particles die).
    @MainActor
    static func playGateOpenAnimation(
        on gateNode: SKNode?,
        revealNodes: [SKNode],
        duration: TimeInterval = gateOpenDuration,
        referenceHeight: CGFloat,
        timingNode: SKNode,
        completion: @escaping () -> Void
    ) {
        let highlight = HighlightConfig.gateOpen
        for revealed in revealNodes {
            revealed.removeAction(forKey: "gateOpenFloorFade")
            revealed.alpha = 0
            let fadeIn = SKAction.fadeIn(withDuration: duration)
            fadeIn.timingMode = .easeInEaseOut
            revealed.run(fadeIn, withKey: "gateOpenFloorFade")
        }

        if let gateNode {
            let visuals = gateNode.children.filter { !($0 is SKEmitterNode) }
            let glow = SparkleEmitterFactory.makeNode(
                config: highlight,
                referenceHeight: referenceHeight
            )
            glow.position = CGPoint(x: 0, y: referenceHeight * CGFloat(highlight.yOffset))
            gateNode.insertChild(glow, at: 0)

            let fadeOut = SKAction.fadeOut(withDuration: duration)
            fadeOut.timingMode = .easeIn
            for child in visuals {
                child.removeAction(forKey: "gateOpenFade")
                child.run(fadeOut, withKey: "gateOpenFade")
            }

            gateNode.removeAction(forKey: "gateOpenDissolve")
            gateNode.run(.sequence([
                .wait(forDuration: duration * 0.75),
                .run { SparkleEmitterFactory.stop(in: gateNode) },
                .wait(forDuration: max(highlight.lifetime, duration * 0.25)),
                .run {
                    gateNode.removeFromParent()
                    completion()
                },
            ]), withKey: "gateOpenDissolve")
            return
        }

        timingNode.removeAction(forKey: "gateOpenDissolve")
        timingNode.run(.sequence([
            .wait(forDuration: duration),
            .run(completion),
        ]), withKey: "gateOpenDissolve")
    }

    /// Red sparkles while the enemy art fades; calls `completion` when finished.
    ///
    /// Particles do not inherit parent alpha, so the sprite/shape children fade
    /// separately and the emitter birth rate is stopped before removal.
    @MainActor
    static func playDefeatAnimation(on node: SKNode, completion: @escaping () -> Void) {
        let highlight = HighlightConfig.enemyDefeat
        let visuals = node.children.filter { !($0 is SKEmitterNode) }
        let animated = visuals.compactMap { $0 as? AnimatedSpriteNode }.first
        let referenceHeight = animated?.targetHeight
            ?? animated?.size.height
            ?? visuals.first?.frame.height
            ?? 40
        let baseY = animated?.position.y ?? visuals.first?.position.y ?? 0

        let glow = SparkleEmitterFactory.makeNode(
            config: highlight,
            referenceHeight: referenceHeight
        )
        glow.position = CGPoint(
            x: 0,
            y: baseY + referenceHeight * CGFloat(highlight.yOffset)
        )
        node.insertChild(glow, at: 0)

        let fadeDuration = max(highlight.lifetime * 0.9, 0.45)
        let fade = SKAction.fadeOut(withDuration: fadeDuration)
        fade.timingMode = .easeIn
        node.run(.sequence([
            .run {
                for child in visuals {
                    child.run(fade)
                }
            },
            .wait(forDuration: fadeDuration * 0.7),
            .run { SparkleEmitterFactory.stop(in: node) },
            .wait(forDuration: highlight.lifetime),
            .run(completion),
        ]), withKey: "defeatFade")
    }

    static func applyAnimationFrame(_ frame: Int, to node: SKNode) {
        let scales: [CGFloat] = [1.0, 1.06, 1.0, 0.94]
        node.setScale(scales[frame % scales.count])
    }

    static func updateEntityNode(
        _ node: SKNode,
        entity: GameEntity,
        config: IsometricConfig,
        gates: [GateOccluder] = []
    ) {
        node.position = IsometricMath.entityScreenPosition(entity.position, config: config)
        applyOcclusionSortZ(
            to: node,
            z: entitySortValueAccountingForGates(
                x: Double(entity.position.x),
                y: Double(entity.position.y),
                story: entity.position.story,
                gates: gates,
                config: config
            )
        )
    }
}
