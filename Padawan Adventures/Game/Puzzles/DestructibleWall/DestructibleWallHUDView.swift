import UIKit

/// Destructible-wall HUD: countdown timer in the upper-trailing corner.
final class DestructibleWallHUDView: UIView {
    private let config: HudConfig
    private let timerLabel = UILabel()

    init(config: HudConfig, timerSeconds: Int) {
        self.config = config
        super.init(frame: .zero)
        setup(timerSeconds: timerSeconds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    func setTimer(seconds: Int, urgent: Bool) {
        timerLabel.text = "\(max(seconds, 0))"
        timerLabel.textColor = urgent ? .systemRed : .white
    }

    private func setup(timerSeconds: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = true

        timerLabel.text = "\(max(timerSeconds, 0))"
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        timerLabel.textAlignment = .right
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.accessibilityIdentifier = "destructible_wall.timer"
        timerLabel.setContentHuggingPriority(.required, for: .horizontal)
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(timerLabel)

        let margin = CGFloat(config.edgeMargin)
        NSLayoutConstraint.activate([
            timerLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            timerLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
    }
}
