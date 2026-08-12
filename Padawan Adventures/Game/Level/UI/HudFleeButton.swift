import SwiftUI
import UIKit

extension GameHUDView {
    static let fleeButtonSize: CGFloat = 52

    @MainActor
    static func makeFleeButton() -> UIButton {
        let plate = AppCircularIconPlate.makeUIImage(
            systemName: "figure.run",
            size: fleeButtonSize
        )
        var configuration = UIButton.Configuration.plain()
        configuration.background.image = plate
        configuration.background.imageContentMode = .scaleToFill
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
