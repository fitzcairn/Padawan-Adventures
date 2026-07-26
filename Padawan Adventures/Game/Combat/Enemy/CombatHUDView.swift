import UIKit

/// Combat-only HUD: health (top-leading), timer (top-trailing), coins (bottom-leading).
final class CombatHUDView: UIView {
    private let config: HudConfig
    private let heartsStack: UIStackView
    private let heartImage: UIImage?
    private let scoreLabel = UILabel()
    private let timerLabel = UILabel()
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    init(config: HudConfig, healthCount: Int, starsCount: Int = 0, timerSeconds: Int) {
        self.config = config
        self.heartsStack = Self.makeIconStack(spacing: config.iconSpacing)
        self.heartImage = HudVitalIcon.health.makeUIImage(pointSize: CGFloat(config.iconSize))
        super.init(frame: .zero)
        setup(healthCount: healthCount, starsCount: starsCount, timerSeconds: timerSeconds)
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

    func setStars(_ count: Int) {
        scoreLabel.text = "\(max(count, 0))"
    }

    func setHealth(_ count: Int) {
        let target = max(count, 0)
        while heartsStack.arrangedSubviews.count > target {
            guard let view = heartsStack.arrangedSubviews.last else { break }
            heartsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        while heartsStack.arrangedSubviews.count < target {
            addIcon(image: heartImage, to: heartsStack)
        }
    }

    func setTimer(seconds: Int, urgent: Bool) {
        timerLabel.text = "\(max(seconds, 0))"
        timerLabel.textColor = urgent ? .systemRed : .white
    }

    private func setup(healthCount: Int, starsCount: Int, timerSeconds: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        // Keep true when hosted by SwiftUI; parent containers may set false + pin edges.
        translatesAutoresizingMaskIntoConstraints = true

        for _ in 0..<max(healthCount, 0) {
            addIcon(image: heartImage, to: heartsStack)
        }

        let score = makeScoreRow(starsCount: starsCount)
        timerLabel.text = "\(max(timerSeconds, 0))"
        timerLabel.textColor = .white
        timerLabel.font = AppFont.uiKit(size: 28, weight: .bold)
        timerLabel.textAlignment = .right
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.applyAppCopyShadow()
        timerLabel.accessibilityIdentifier = "combat.timer"
        // Avoid collapsing to zero width before first layout pass.
        timerLabel.setContentHuggingPriority(.required, for: .horizontal)
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(heartsStack)
        addSubview(timerLabel)
        addSubview(score)

        let heartsTop = heartsStack.topAnchor.constraint(equalTo: topAnchor)
        let heartsLeading = heartsStack.leadingAnchor.constraint(equalTo: leadingAnchor)
        let timerTop = timerLabel.topAnchor.constraint(equalTo: topAnchor)
        let timerTrailing = timerLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        let scoreBottom = score.bottomAnchor.constraint(equalTo: bottomAnchor)
        let scoreLeading = score.leadingAnchor.constraint(equalTo: leadingAnchor)

        edgeInsets.addTop(heartsTop)
        edgeInsets.addLeading(heartsLeading)
        edgeInsets.addTop(timerTop)
        edgeInsets.addTrailing(timerTrailing)
        edgeInsets.addBottom(scoreBottom)
        edgeInsets.addLeading(scoreLeading)

        NSLayoutConstraint.activate([
            heartsTop,
            heartsLeading,

            timerTop,
            timerTrailing,
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            scoreBottom,
            scoreLeading,
        ])
        edgeInsets.update()
    }

    private func addIcon(image: UIImage?, to stack: UIStackView) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let size = CGFloat(config.iconSize)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])
        stack.addArrangedSubview(imageView)
    }

    private static func makeIconStack(spacing: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(spacing)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeScoreRow(starsCount: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(config.scoreTextGap)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let size = CGFloat(config.iconSize)
        let coin = ScoreCoinIcon.makeImageView(side: size)

        scoreLabel.text = "\(max(starsCount, 0))"
        scoreLabel.textColor = .white
        scoreLabel.font = AppFont.uiKit(size: 22, weight: .semibold)
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        scoreLabel.applyAppCopyShadow()
        scoreLabel.accessibilityIdentifier = "combat.stars"
        scoreLabel.setContentHuggingPriority(.required, for: .horizontal)
        scoreLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.addArrangedSubview(coin)
        stack.addArrangedSubview(scoreLabel)
        return stack
    }
}
