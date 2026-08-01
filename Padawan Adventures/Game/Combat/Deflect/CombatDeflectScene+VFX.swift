import SpriteKit
import UIKit

extension CombatDeflectScene {
    // MARK: - VFX

    func playDamage(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "damage", from: playerFx)
        flashNode(playerNode, color: .orange, actionKey: playerFlashActionKey)

        let highlight = HighlightConfig.combatImpact
        let referenceHeight = max(orbBaseSize, playerSpriteHeight * 0.3)
        let burst = SparkleEmitterFactory.makeBurstNode(
            config: highlight,
            referenceHeight: referenceHeight
        )
        burst.position = position
        burst.zPosition = Layer.vfx
        addChild(burst)

        let linger = max(highlight.lifetime * 1.6, 0.7)
        burst.run(.sequence([
            .wait(forDuration: linger),
            .removeFromParent(),
        ]))
    }

    func playExplosion(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "slash_hit", from: playerFx)
        let circle = SKShapeNode(circleOfRadius: 12)
        circle.fillColor = .yellow
        circle.strokeColor = UIColor.orange
        circle.lineWidth = 2
        circle.position = position
        circle.zPosition = Layer.vfx
        addChild(circle)

        let grow = SKAction.scale(to: 3.5, duration: 0.2)
        let fade = SKAction.fadeOut(withDuration: 0.2)
        circle.run(SKAction.group([grow, fade])) {
            circle.removeFromParent()
        }
    }

    // MARK: - End states

    func finishWin(starsAwarded: Int) {
        guard !didEnd else { return }
        didEnd = true
        GameLogger.mark(.combat, "deflect win (stars: \(starsAwarded))")
        engine.end()
        removeAction(forKey: nextOrbActionKey)
        removeOrbNode()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "win")
        deflectDelegate?.combatDeflectSceneDidWin(starsAwarded: starsAwarded)
    }

    func finishLose() {
        guard !didEnd else { return }
        didEnd = true
        GameLogger.mark(.combat, "deflect loss")
        engine.end()
        removeAction(forKey: nextOrbActionKey)
        removeOrbNode()
        stopCombatLoop()
        SoundEffectsController.shared.playCommon(event: "lose")
        deflectDelegate?.combatDeflectSceneDidLose()
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
