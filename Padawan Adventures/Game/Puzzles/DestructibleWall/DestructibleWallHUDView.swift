import UIKit

/// Destructible-wall HUD: countdown timer in the upper-trailing corner.
final class DestructibleWallHUDView: UIView {
    private let timerLabel = UILabel()
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    init(config: HudConfig, timerSeconds: Int) {
        super.init(frame: .zero)
        _ = config
        setup(timerSeconds: timerSeconds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeInsets.update()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        edgeInsets.update()
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

        let timerTop = timerLabel.topAnchor.constraint(equalTo: topAnchor)
        let timerTrailing = timerLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        edgeInsets.addTop(timerTop)
        edgeInsets.addTrailing(timerTrailing)

        NSLayoutConstraint.activate([
            timerTop,
            timerTrailing,
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
        edgeInsets.update()
    }
}
