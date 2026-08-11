import SpriteKit
import SwiftUI
import UIKit

/// Shared in-scene monster HP / damage bar used by every combat arena.
/// Sits to the right of the enemy, pinned near the top of the screen.
enum CombatMonsterHPBar {
    static let height: CGFloat = 28
    static let widthFraction: CGFloat = 0.22
    /// Gap between the enemy's right edge and the bar's left edge.
    static let leadingGap: CGFloat = 12
    static let nodeName = "monsterHP"
    static let pulseActionKey = "monsterHPPulse"

    static func makeTrack(zPosition: CGFloat) -> SKSpriteNode {
        let track = SKSpriteNode(color: .clear, size: .zero)
        track.anchorPoint = CGPoint(x: 0, y: 0.5)
        track.zPosition = zPosition
        track.name = nodeName
        return track
    }

    /// Positions `track` to the right of `enemy`, near the top of `scene`.
    static func layout(
        _ track: SKSpriteNode,
        beside enemy: SKNode,
        in scene: SKScene,
        fraction: CGFloat
    ) {
        let frame = enemy.calculateAccumulatedFrame()
        let barSize = CGSize(
            width: scene.size.width * widthFraction,
            height: height
        )
        track.size = barSize
        // Pin near the scene top so both arenas share the same chrome height,
        // regardless of how tall the enemy sprite is.
        let y = scene.size.height - scene.chromeInsets.top - barSize.height * 0.5
        track.position = CGPoint(x: frame.maxX + leadingGap, y: y)
        applyTexture(to: track, fraction: fraction)
    }

    static func applyTexture(to track: SKSpriteNode, fraction: CGFloat) {
        let clamped = min(max(fraction, 0), 1)
        let fill = Color(uiColor: CombatHUDView.color(forProgress: clamped))
        track.texture = StarWarsConsoleProgressBar.makeTexture(
            progress: Double(clamped),
            size: track.size,
            fillColor: fill
        )
    }

    static func animatePulse(_ track: SKSpriteNode, fraction: CGFloat) {
        applyTexture(to: track, fraction: fraction)
        track.run(
            .sequence([
                .fadeAlpha(to: 0.65, duration: 0.06),
                .fadeAlpha(to: 1, duration: 0.14),
            ]),
            withKey: pulseActionKey
        )
    }
}
