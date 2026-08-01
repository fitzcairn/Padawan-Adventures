import SpriteKit
import UIKit

extension CombatScene {
    func playDamage(at position: CGPoint) {
        SoundEffectsController.shared.play(event: "damage", from: playerFx)
        flashPlayer(color: .orange)

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

    func playIncorrectSlash(at position: CGPoint) {
        playSlashErrorSound()

        let container = SKNode()
        container.position = position
        container.zPosition = 45
        addChild(container)

        let flash = SKShapeNode(circleOfRadius: 22)
        flash.fillColor = UIColor.systemBlue.withAlphaComponent(0.35)
        flash.strokeColor = UIColor.systemBlue
        flash.lineWidth = 2
        container.addChild(flash)

        // Distinct from the yellow correct explode: a blue "X".
        for angle in [CGFloat.pi / 4, -CGFloat.pi / 4] {
            let bar = SKShapeNode(rectOf: CGSize(width: 44, height: 6), cornerRadius: 2)
            bar.fillColor = .systemBlue
            bar.strokeColor = .white
            bar.lineWidth = 1
            bar.zRotation = angle
            container.addChild(bar)
        }

        let pop = SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.35, duration: 0.08),
                SKAction.fadeAlpha(to: 1, duration: 0.05),
            ]),
            SKAction.wait(forDuration: 0.06),
            SKAction.group([
                SKAction.scale(to: 1.7, duration: 0.18),
                SKAction.fadeOut(withDuration: 0.18),
            ]),
            SKAction.removeFromParent(),
        ])
        container.setScale(0.7)
        container.run(pop)
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
