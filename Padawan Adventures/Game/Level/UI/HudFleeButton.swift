import UIKit

extension GameHUDView {
    static let fleeButtonSize: CGFloat = 52

    static func makeFleeButton() -> UIButton {
        let symbol = UIImage.SymbolConfiguration(
            pointSize: fleeButtonSize * 0.42,
            weight: .semibold
        )
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "figure.run", withConfiguration: symbol)
        configuration.baseForegroundColor = AppChrome.uiButtonForegroundColor
        configuration.baseBackgroundColor = AppChrome.uiButtonBackgroundColor
        configuration.background.strokeColor = AppChrome.uiButtonOutlineColor
        configuration.background.strokeWidth = AppChrome.buttonOutlineWidth
        configuration.background.cornerRadius = fleeButtonSize / 2
        configuration.cornerStyle = .fixed
        configuration.contentInsets = .zero

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = Strings.text("hud_flee")
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: fleeButtonSize),
            button.heightAnchor.constraint(equalToConstant: fleeButtonSize),
        ])
        return button
    }

    @objc func fleeTapped() {
        onFleeTapped?()
    }
}
