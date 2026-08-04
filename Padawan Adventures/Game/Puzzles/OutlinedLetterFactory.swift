import SpriteKit
import UIKit

/// White-on-black outlined letter stacks for gate spelling minigames (SpriteKit).
enum OutlinedLetterFactory {
    enum Style {
        /// Fixed 2pt outline for capacitor-face letters at gate puzzle sizes.
        case capacitorFace
        /// Scales outline/shadow with font size (letter-match, word-plug).
        case proportional
    }

    static func make(
        text: String,
        fontSize: CGFloat,
        style: Style = .proportional,
        /// Decorative letter stacks must not steal scene taps (SpriteKit delivers
        /// touches to the deepest interactive node). Default is non-interactive.
        disablesInteraction: Bool = true
    ) -> SKNode {
        let root = SKNode()
        root.isUserInteractionEnabled = false
        let (outlineOffset, shadowOffset) = offsets(for: fontSize, style: style)

        for dx in -1...1 {
            for dy in -1...1 {
                guard dx != 0 || dy != 0 else { continue }
                let outline = SKLabelNode(text: text)
                outline.fontName = AppFont.name
                outline.fontSize = fontSize
                outline.fontColor = .black
                outline.verticalAlignmentMode = .center
                outline.horizontalAlignmentMode = .center
                outline.position = CGPoint(
                    x: CGFloat(dx) * outlineOffset,
                    y: CGFloat(dy) * outlineOffset
                )
                outline.zPosition = SceneLayer.LabelStack.outline
                outline.isUserInteractionEnabled = !disablesInteraction
                root.addChild(outline)
            }
        }

        let innerShadow = SKLabelNode(text: text)
        innerShadow.fontName = AppFont.name
        innerShadow.fontSize = fontSize
        innerShadow.fontColor = UIColor.black.withAlphaComponent(0.45)
        innerShadow.verticalAlignmentMode = .center
        innerShadow.horizontalAlignmentMode = .center
        // Slightly up-left so the fill covers most of it → thin inset shadow.
        innerShadow.position = CGPoint(x: -shadowOffset, y: shadowOffset)
        innerShadow.zPosition = SceneLayer.LabelStack.innerShadow
        innerShadow.isUserInteractionEnabled = !disablesInteraction
        root.addChild(innerShadow)

        let label = SKLabelNode(text: text)
        label.fontName = AppFont.name
        label.fontSize = fontSize
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = SceneLayer.LabelStack.fill
        label.isUserInteractionEnabled = !disablesInteraction
        root.addChild(label)

        return root
    }

    private static func offsets(for fontSize: CGFloat, style: Style) -> (CGFloat, CGFloat) {
        switch style {
        case .capacitorFace:
            return (2, 2)
        case .proportional:
            return (max(1.0, fontSize * 0.06), max(0.75, fontSize * 0.035))
        }
    }
}
