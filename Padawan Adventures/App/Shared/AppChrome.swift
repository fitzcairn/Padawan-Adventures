import UIKit

enum AppChrome {
    static let backgroundColor = UIColor.black
    static let primaryTextColor = UIColor.white
    static let secondaryTextColor = UIColor(white: 0.65, alpha: 1)

    static func makeCenteredLabel(_ text: String, size: CGFloat = 28, weight: UIFont.Weight = .medium) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = primaryTextColor
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func makeLargeButton(title: String, action: Selector, target: Any) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .black
        config.baseBackgroundColor = UIColor(white: 0.92, alpha: 1)
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 28, bottom: 18, trailing: 28)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 22, weight: .semibold)
            return outgoing
        }

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(target, action: action, for: .touchUpInside)
        return button
    }

    static var versionBuildString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "v\(version) (\(build))"
    }
}
