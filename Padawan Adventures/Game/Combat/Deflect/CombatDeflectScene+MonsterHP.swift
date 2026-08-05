import SpriteKit

extension CombatDeflectScene {
    // MARK: - Monster HP bar

    func buildMonsterHPBar() {
        hpTrack?.removeFromParent()
        let track = CombatMonsterHPBar.makeTrack(zPosition: Layer.hpBar)
        addChild(track)
        hpTrack = track
        layoutMonsterHPBar()
    }

    func layoutMonsterHPBar() {
        guard let hpTrack, let enemyNode else { return }
        CombatMonsterHPBar.layout(
            hpTrack,
            beside: enemyNode,
            in: self,
            fraction: monsterHPFraction
        )
    }

    /// Full and green at the start, draining toward red as the monster is worn down.
    var monsterHPFraction: CGFloat {
        let total = max(engine.config.monsterHP, 1)
        return min(max(CGFloat(engine.monsterHP) / CGFloat(total), 0), 1)
    }

    func animateMonsterHPBar() {
        guard let hpTrack else { return }
        CombatMonsterHPBar.animatePulse(hpTrack, fraction: monsterHPFraction)
    }
}
