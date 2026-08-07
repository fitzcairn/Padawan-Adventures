import SpriteKit
import UIKit

/// White-on-black outlined letter stacks for gate spelling minigames (SpriteKit).
enum OutlinedLetterFactory {
    /// Node name of the colored fill label, so callers can recolor a built stack.
    static let fillNodeName = "outlinedLetterFill"
    /// Node name of the colored blank rectangle stroke (empty box).
    static let blankFillNodeName = "outlinedBlankFill"
    /// `userData` key storing the font size used to build a blank/letter stack.
    static let fontSizeUserDataKey = "fontSize"

    enum Style {
        /// Fixed 2pt outline for capacitor-face letters at gate puzzle sizes.
        case capacitorFace
        /// Scales outline/shadow with font size (letter-match, word-plug).
        case proportional
    }

    /// Underscore advance × 1.2 × cap height for a missing-letter blank at `fontSize`.
    static func blankSize(fontSize: CGFloat) -> CGSize {
        let font = AppFont.uiKit(size: max(1, fontSize))
        let width = ceil(("_" as NSString).size(withAttributes: [.font: font]).width)
        let height = max(1, font.capHeight) * 1.2
        return CGSize(width: width, height: height)
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
        storeFontSize(fontSize, on: root)
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
        label.name = fillNodeName
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

    /// Empty outlined blank rectangle (underscore width × 1.2 × cap height).
    /// Vertically centered on the mid of surrounding spelling (cap height / 2 above baseline).
    static func makeBlank(
        fontSize: CGFloat,
        style: Style = .proportional,
        disablesInteraction: Bool = true
    ) -> SKNode {
        let root = SKNode()
        root.isUserInteractionEnabled = false
        storeFontSize(fontSize, on: root)

        let font = AppFont.uiKit(size: max(1, fontSize))
        let stringHeight = max(1, font.capHeight)
        let size = blankSize(fontSize: fontSize)
        let rect = CGRect(
            x: -size.width * 0.5,
            y: stringHeight * 0.5 - size.height * 0.5,
            width: size.width,
            height: size.height
        )
        let lineWidth = max(1.5, fontSize * 0.08)
        let (outlineOffset, _) = offsets(for: fontSize, style: style)

        for dx in -1...1 {
            for dy in -1...1 {
                guard dx != 0 || dy != 0 else { continue }
                let outline = SKShapeNode(rect: rect)
                outline.fillColor = .clear
                outline.strokeColor = .black
                outline.lineWidth = lineWidth
                outline.position = CGPoint(
                    x: CGFloat(dx) * outlineOffset,
                    y: CGFloat(dy) * outlineOffset
                )
                outline.zPosition = SceneLayer.LabelStack.outline
                outline.isUserInteractionEnabled = !disablesInteraction
                root.addChild(outline)
            }
        }

        let stroke = SKShapeNode(rect: rect)
        stroke.name = blankFillNodeName
        stroke.fillColor = .clear
        stroke.strokeColor = .white
        stroke.lineWidth = lineWidth
        stroke.zPosition = SceneLayer.LabelStack.fill
        stroke.isUserInteractionEnabled = !disablesInteraction
        root.addChild(stroke)

        return root
    }

    /// Colored fill of a stack built by `make(text:…)`, for recoloring in place.
    static func fillLabel(in root: SKNode) -> SKLabelNode? {
        root.childNode(withName: fillNodeName) as? SKLabelNode
    }

    /// Colored blank stroke built by `makeBlank(fontSize:)`, for recoloring in place.
    static func blankFill(in root: SKNode) -> SKShapeNode? {
        root.childNode(withName: blankFillNodeName) as? SKShapeNode
    }

    static func fontSize(from root: SKNode) -> CGFloat? {
        (root.userData?[fontSizeUserDataKey] as? NSNumber).map { CGFloat(truncating: $0) }
    }

    private static func storeFontSize(_ fontSize: CGFloat, on root: SKNode) {
        let data = root.userData ?? NSMutableDictionary()
        data[fontSizeUserDataKey] = NSNumber(value: Double(fontSize))
        root.userData = data
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
