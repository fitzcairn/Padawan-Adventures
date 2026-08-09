import SpriteKit
import UIKit

extension CombatScene {
    func playDamage(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "damage", from: playerFx)
        flashPlayer(color: .orange)
        impactBurstVisual(at: position)
    }

    func impactBurstVisual(at position: CGPoint) {
        let highlight = HighlightConfig.combatImpact
        let referenceHeight = max(shotBaseSize, playerSpriteHeight * 0.3)
        let burst = SparkleEmitterFactory.makeBurstNode(
            config: highlight,
            referenceHeight: referenceHeight
        )
        burst.position = position
        burst.zPosition = 40
        addChild(burst)

        let linger = max(highlight.lifetime * 1.6, 0.7)
        burst.run(.sequence([
            .wait(forDuration: linger),
            .removeFromParent(),
        ]))
    }

    /// Temporary colorize pulse on the player sprite.
    func flashPlayer(color: UIColor, hold: TimeInterval = 0.08, gap: TimeInterval = 0.05) {
        flashNode(
            playerNode,
            color: color,
            hold: hold,
            gap: gap,
            actionKey: playerFlashActionKey
        )
    }

    func playExplosion(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "slash_hit", from: playerFx)
        explosionVisual(at: position)
    }

    func explosionVisual(at position: CGPoint) {
        let circle = SKShapeNode(circleOfRadius: 12)
        circle.fillColor = .yellow
        circle.strokeColor = UIColor.orange
        circle.lineWidth = 2
        circle.position = position
        circle.zPosition = 40
        addChild(circle)

        let grow = SKAction.scale(to: 3.5, duration: 0.2)
        let fade = SKAction.fadeOut(withDuration: 0.2)
        circle.run(SKAction.group([grow, fade])) {
            circle.removeFromParent()
        }
    }

    /// Red flash, then dissolve with the explosion VFX for a wrongly slashed letter.
    func flashRedFadeAndExplode(_ node: SKNode, at position: CGPoint) {
        if let sprite = node as? SKSpriteNode {
            sprite.color = .systemRed
            sprite.colorBlendFactor = 0.85
        } else if let shape = node as? SKShapeNode {
            shape.fillColor = .systemRed
            shape.strokeColor = .white
        }
        let flashHold: TimeInterval = 0.08
        node.run(.sequence([
            .wait(forDuration: flashHold),
            .run { [weak self] in
                self?.explosionVisual(at: position)
            },
            .group([
                .scale(by: 1.2, duration: 0.22),
                .fadeOut(withDuration: 0.22),
            ]),
            .removeFromParent(),
        ]))
    }

    func playSlashErrorSound() {
        SoundEffectsController.shared.playCommon(event: "error")
    }

    // MARK: - End states

    func finishWin() {
        guard !didEnd else { return }
        didEnd = true
        engine.end()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "win")
        for id in Array(shotVisuals.keys) {
            removeShotNode(id: id)
        }
        clearSlashLine()
        let awarded = engine.config.starsToWin
        combatDelegate?.combatSceneDidWin(starsAwarded: awarded)
    }

    func finishLose() {
        guard !didEnd else { return }
        didEnd = true
        engine.end()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "lose")
        clearSlashLine()
        combatDelegate?.combatSceneDidLose()
    }

    func stopCombatLoop() {
        SoundEffectsController.shared.stopLoop(trackID: activeLoopTrackID)
        activeLoopTrackID = nil
        clearCombatMix()
    }

    func clearCombatMix() {
        SoundEffectsController.shared.setCombatMixActive(false)
        BackgroundMusicController.shared.setCombatMixActive(false)
    }
}
