import SpriteKit
import SwiftUI
import UIKit

extension CombatScene {
    // MARK: - Monster HP / damage bar

    func buildMonsterHPBar() {
        hpTrack?.removeFromParent()

        let track = SKSpriteNode(color: .clear, size: .zero)
        track.anchorPoint = CGPoint(x: 0, y: 0.5)
        track.zPosition = Layer.hpBar
        track.name = "monsterHP"
        addChild(track)
        hpTrack = track

        layoutMonsterHPBar()
    }

    /// Sits directly to the right of the monster, vertically centered on it.
    func layoutMonsterHPBar() {
        guard let hpTrack, let enemyNode else { return }
        let frame = enemyNode.calculateAccumulatedFrame()
        let width = size.width * 0.22
        let height: CGFloat = 28
        let barSize = CGSize(width: width, height: height)
        hpTrack.size = barSize
        hpTrack.position = CGPoint(x: frame.maxX + 12, y: frame.midY)
        hpTrack.texture = makeMonsterHPTexture(size: barSize, fraction: monsterHPFraction)
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
        let fraction = monsterHPFraction
        hpTrack.texture = makeMonsterHPTexture(size: hpTrack.size, fraction: fraction)
        hpTrack.run(
            .sequence([
                .fadeAlpha(to: 0.65, duration: 0.06),
                .fadeAlpha(to: 1, duration: 0.14),
            ]),
            withKey: "monsterHPPulse"
        )
    }

    private func makeMonsterHPTexture(size: CGSize, fraction: CGFloat) -> SKTexture {
        let fill = Color(uiColor: CombatHUDView.color(forProgress: fraction))
        return StarWarsConsoleProgressBar.makeTexture(
            progress: Double(fraction),
            size: size,
            fillColor: fill
        )
    }
}
