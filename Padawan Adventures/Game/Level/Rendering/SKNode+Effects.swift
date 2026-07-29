import SpriteKit
import UIKit

/// Rounded additive-friendly stroke used for lightsaber blades and electric arcs.
func makeGlowStroke(
    path: CGPath? = nil,
    lineWidth: CGFloat,
    color: UIColor,
    glowWidth: CGFloat
) -> SKShapeNode {
    let node: SKShapeNode
    if let path {
        node = SKShapeNode(path: path)
    } else {
        node = SKShapeNode()
    }
    node.fillColor = .clear
    node.strokeColor = color
    node.lineWidth = lineWidth
    node.lineCap = .round
    node.lineJoin = .round
    node.glowWidth = glowWidth
    node.isAntialiased = true
    return node
}

extension SKAction {
    /// `count` on/off blinks at `period` seconds each, for wrong-answer feedback.
    static func doubleFlash(
        period: TimeInterval = 0.12,
        count: Int = 2,
        apply: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> SKAction {
        .repeat(
            .sequence([
                .run(apply),
                .wait(forDuration: period),
                .run(clear),
                .wait(forDuration: period),
            ]),
            count: count
        )
    }
}
