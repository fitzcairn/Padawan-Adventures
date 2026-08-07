import SpriteKit
import UIKit

/// Shared "tap to hear this" affordance: a white `play` triangle that fills while its
/// sound plays. SKTexture ignores UIImage tints and draws SF Symbols as flat black
/// templates, so the white tint has to be baked into a bitmap.
enum MinigamePlaySoundIcon {
    static let idleSymbol = "play"
    static let activeSymbol = "play.fill"
    /// `play` is optically left-heavy; callers nudge by this fraction of the face width.
    static let opticalXNudgeRatio: CGFloat = 0.03

    private static var cache: [String: SKTexture] = [:]

    static func texture(systemName: String, side: CGFloat) -> SKTexture {
        let rounded = max(side.rounded(), 1)
        let key = "\(systemName):\(Int(rounded))"
        if let cached = cache[key] { return cached }
        let config = UIImage.SymbolConfiguration(pointSize: rounded, weight: .bold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config) else {
            return SKTexture()
        }
        let size = CGSize(width: rounded, height: rounded)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            symbol
                .withTintColor(.white, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    static func makeNode(side: CGFloat, name: String) -> SKSpriteNode {
        let node = SKSpriteNode(
            texture: texture(systemName: idleSymbol, side: side),
            size: CGSize(width: side, height: side)
        )
        node.name = name
        node.isUserInteractionEnabled = false
        return node
    }

    /// Shows `play.fill` for the length of `trackID`, then restores the outline.
    static func pulse(
        _ icon: SKSpriteNode,
        forTrackID trackID: String,
        actionKey: String = "playSoundIconPulse"
    ) {
        let side = max(icon.size.width, icon.size.height)
        let idle = texture(systemName: idleSymbol, side: side)
        let active = texture(systemName: activeSymbol, side: side)
        icon.removeAction(forKey: actionKey)
        icon.texture = active
        icon.run(
            SKAction.sequence([
                SKAction.wait(
                    forDuration: SoundEffectsController.shared.cueDuration(of: trackID)
                ),
                SKAction.run { [weak icon] in icon?.texture = idle },
            ]),
            withKey: actionKey
        )
    }
}
