import SwiftUI
import UIKit


extension AppChrome {
    static let backgroundColor = Color.black
    static let primaryTextColor = Color.white
    static let secondaryTextColor = Color(white: 0.65)
    static let buttonBackgroundColor = Color(red: 36 / 255, green: 90 / 255, blue: 133 / 255)
    static let buttonForegroundColor = Color.white
    static let buttonOutlineColor = Color(red: 9 / 255, green: 135 / 255, blue: 232 / 255)
    static let buttonOutlineWidth: CGFloat = 2
    static let copyShadowColor = Color(red: 36 / 255, green: 90 / 255, blue: 133 / 255)
    static let copyShadowRadius: CGFloat = 0
    static let copyShadowY: CGFloat = 2
    static let controlAccentColor = Color(white: 0.92)
    static let maxContentWidth: CGFloat = 420

    static var versionBuildString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "v\(version) (\(build))"
    }

    static var uiButtonBackgroundColor: UIColor {
        UIColor(red: 36 / 255, green: 90 / 255, blue: 133 / 255, alpha: 1)
    }
    static var uiButtonForegroundColor: UIColor { .white }
    static var uiButtonOutlineColor: UIColor {
        UIColor(red: 9 / 255, green: 135 / 255, blue: 232 / 255, alpha: 1)
    }
    static var uiCopyShadowColor: UIColor {
        UIColor(red: 36 / 255, green: 90 / 255, blue: 133 / 255, alpha: 1)
    }

    /// #245a85 drop shadow for non-button copy.
    static func applyCopyShadow(to layer: CALayer) {
        layer.shadowColor = uiCopyShadowColor.cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = copyShadowRadius
        layer.shadowOffset = CGSize(width: 0, height: copyShadowY)
        layer.masksToBounds = false
    }
}

enum AppFont {
    /// PostScript name — use for UIFont, Font.custom, and SKLabelNode.fontName.
    static let name = "Conthrax-SemiBold"

    /// SwiftUI text. `weight` is ignored (single face); kept so call sites can mirror old `.system(size:weight:)` shape.
    static func swiftUI(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        _ = weight
        return .custom(name, size: size)
    }

    /// UIKit labels / attributed strings / button transformers.
    static func uiKit(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}
