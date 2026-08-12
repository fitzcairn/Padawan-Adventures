import SpriteKit
import SwiftUI
import UIKit

/// Shared look for the "Tap to continue" hint so every tutorial renders it at the
/// same size, whether it is drawn by SwiftUI (minigames) or SpriteKit (world).
enum TutorialHintStyle {
    static let fontSize: CGFloat = 15

    static let font = AppFont.swiftUI(size: fontSize, weight: .semibold)

    static var color: Color { AppChrome.primaryTextColor }

    /// Hint label for SpriteKit scenes. The caller owns position, `zPosition` and alpha.
    static func makeLabel(text: String) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontName = AppFont.name
        label.fontSize = fontSize
        label.fontColor = UIColor(color)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .bottom
        return label
    }
}
