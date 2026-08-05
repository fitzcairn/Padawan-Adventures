import SpriteKit

extension CombatScene {
    // MARK: - Monster HP / damage bar

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

    /// Remaining monster "HP" as a fraction of `starsToWin`.
    /// Full and green at the start, draining toward red as waves are cleared.
    var monsterHPFraction: CGFloat {
        let total = max(engine.config.starsToWin, 1)
        let remaining = max(total - engine.combatStars, 0)
        return min(max(CGFloat(remaining) / CGFloat(total), 0), 1)
    }

    func animateMonsterHPBar() {
        guard let hpTrack else { return }
        CombatMonsterHPBar.animatePulse(hpTrack, fraction: monsterHPFraction)
    }
}
