import SpriteKit
import UIKit

/// Layout, motion, and VFX helpers shared by the combat arenas (`CombatScene`,
/// `CombatDeflectScene`) so the two cannot drift apart.
///
/// All of these assume the arena convention: `anchorPoint = .zero` (bottom-left origin)
/// with `AnimatedSpriteNode`s positioned by their feet.
extension SKScene {
    /// Body aim point (feet + half height). `AnimatedSpriteNode` extends upward from feet.
    func bodyCenter(of node: AnimatedSpriteNode, height: CGFloat) -> CGPoint {
        CGPoint(x: node.position.x, y: node.position.y + height * 0.5)
    }

    /// Pins the sprite's top-most middle opaque pixel to the view's top-middle.
    func pinToTopOfView(_ node: AnimatedSpriteNode, height: CGFloat) {
        node.fitHeight(height)
        // Measure from a known position, then shift so content top == scene top.
        node.position = CGPoint(x: size.width * 0.5, y: 0)
        let frame = node.calculateAccumulatedFrame()
        let topPadding = topOpaqueInsetPoints(for: node)
        // Quad top → scene top, then nudge up by transparent padding above content.
        let dy = size.height - frame.maxY + topPadding
        node.position = CGPoint(x: size.width * 0.5, y: dy)
    }

    /// Transparent padding above the opaque content, in scene points.
    func topOpaqueInsetPoints(for node: AnimatedSpriteNode) -> CGFloat {
        guard let texture = node.texture else { return 0 }
        let image = texture.cgImage()
        let imageHeight = CGFloat(image.height)
        guard imageHeight > 0 else { return 0 }
        guard let bounds = SpriteSheetLoader.opaqueContentBounds(of: image) else { return 0 }
        let visualHeight = node.size.height * abs(node.yScale)
        return CGFloat(bounds.minY) / imageHeight * visualHeight
    }

    /// Visible (opaque) width of `node` in scene points, ignoring transparent padding.
    /// Falls back to the node's full width when the texture cannot be inspected.
    func opaqueContentWidthPoints(for node: AnimatedSpriteNode) -> CGFloat {
        let fullWidth = node.size.width * abs(node.xScale)
        guard let texture = node.texture else { return fullWidth }
        let image = texture.cgImage()
        guard image.width > 0,
              let bounds = SpriteSheetLoader.opaqueContentBounds(of: image) else {
            return fullWidth
        }
        let fraction = bounds.width / CGFloat(image.width)
        guard fraction > 0.05 else { return fullWidth }
        return fullWidth * fraction
    }

    func quadraticBezier(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let u = 1 - t
        let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
        let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    /// Temporary colorize pulse on a sprite (damage / impact feedback).
    func flashNode(
        _ node: SKSpriteNode?,
        color: UIColor,
        hold: TimeInterval = 0.08,
        gap: TimeInterval = 0.05,
        actionKey: String = "spriteFlash"
    ) {
        guard let node else { return }
        node.removeAction(forKey: actionKey)

        let paint = SKAction.run { [weak node] in
            node?.color = color
            node?.colorBlendFactor = 0.7
        }
        let clear = SKAction.run { [weak node] in
            node?.colorBlendFactor = 0
        }
        let pulse = SKAction.sequence([
            paint,
            SKAction.wait(forDuration: hold),
            clear,
            SKAction.wait(forDuration: gap),
        ])
        node.run(SKAction.sequence([pulse, pulse]), withKey: actionKey)
    }
}
