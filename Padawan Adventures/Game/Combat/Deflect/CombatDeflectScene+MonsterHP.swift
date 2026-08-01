import SpriteKit
import UIKit

extension CombatDeflectScene {
    // MARK: - Monster HP bar

    func buildMonsterHPBar() {
        hpTrack?.removeFromParent()

        let track = SKSpriteNode(color: UIColor.white.withAlphaComponent(0.22), size: .zero)
        track.anchorPoint = CGPoint(x: 0, y: 0.5)
        track.zPosition = Layer.hpBar
        track.name = "monsterHP"
        addChild(track)
        hpTrack = track

        let fill = SKSpriteNode(color: CombatHUDView.color(forProgress: 1), size: .zero)
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.zPosition = 1
        track.addChild(fill)
        hpFill = fill

        layoutMonsterHPBar()
    }

    /// Sits directly to the right of the monster, vertically centered on it.
    func layoutMonsterHPBar() {
        guard let hpTrack, let hpFill, let enemyNode else { return }
        let frame = enemyNode.calculateAccumulatedFrame()
        let width = size.width * 0.18
        let height: CGFloat = 18
        hpTrack.size = CGSize(width: width, height: height)
        hpTrack.position = CGPoint(x: frame.maxX + 12, y: frame.midY)
        hpFill.position = .zero
        hpFill.size = CGSize(width: width * monsterHPFraction, height: height)
        hpFill.color = CombatHUDView.color(forProgress: monsterHPFraction)
    }

    var monsterHPFraction: CGFloat {
        let total = max(engine.config.monsterHP, 1)
        return min(max(CGFloat(engine.monsterHP) / CGFloat(total), 0), 1)
    }

    /// Full and green at the start, draining toward red as the monster is worn down.
    func animateMonsterHPBar() {
        guard let hpTrack, let hpFill else { return }
        let fraction = monsterHPFraction
        hpFill.run(.resize(toWidth: hpTrack.size.width * fraction, duration: 0.22))
        hpFill.color = CombatHUDView.color(forProgress: fraction)
    }
}
