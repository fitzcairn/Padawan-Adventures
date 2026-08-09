import SpriteKit
import UIKit

/// Shared "tap to hear this" affordance: a white speaker/bubble icon that fills while its
/// sound plays. SKTexture ignores UIImage tints and draws SF Symbols as flat black
/// templates, so the white tint has to be baked into a bitmap.
enum MinigamePlaySoundIcon {
    static let nodeName = "minigamePlaySoundIcon"
    static let actionKey = "playSoundIconPulse"
    static let idleSymbol = "speaker.wave.2.bubble"
    static let activeSymbol = "speaker.wave.2.bubble.fill"
    /// Speaker bubble is optically left-heavy; callers nudge by this fraction of the
    /// container (tile / capacitor / icon) width.
    static let opticalXNudgeRatio: CGFloat = 0.03

    private static var cache: [String: SKTexture] = [:]

    static func opticalXOffset(containerWidth: CGFloat) -> CGFloat {
        containerWidth * opticalXNudgeRatio
    }

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

    static func makeNode(side: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(
            texture: texture(systemName: idleSymbol, side: side),
            size: CGSize(width: side, height: side)
        )
        node.name = nodeName
        node.isUserInteractionEnabled = false
        return node
    }

    static func find(in parent: SKNode) -> SKSpriteNode? {
        parent.childNode(withName: nodeName) as? SKSpriteNode
    }

    /// Shows the filled symbol for the length of `trackID`, then restores the outline.
    static func pulse(_ icon: SKSpriteNode, forTrackID trackID: String) {
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

    /// Pulses the shared icon that is a direct child of `parent`, if present.
    static func pulse(in parent: SKNode, forTrackID trackID: String) {
        guard let icon = find(in: parent) else { return }
        pulse(icon, forTrackID: trackID)
    }

    /// Pulses every shared icon at or under `node`.
    static func pulseAll(in node: SKNode, forTrackID trackID: String) {
        if let icon = node as? SKSpriteNode, icon.name == nodeName {
            pulse(icon, forTrackID: trackID)
        }
        for child in node.children {
            pulseAll(in: child, forTrackID: trackID)
        }
    }

    static func cancelPulse(_ icon: SKNode) {
        icon.removeAction(forKey: actionKey)
    }

    static func cancelPulse(in parent: SKNode) {
        guard let icon = find(in: parent) else { return }
        cancelPulse(icon)
    }
}
