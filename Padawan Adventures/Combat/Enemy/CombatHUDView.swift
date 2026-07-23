import UIKit

/// Combat-only HUD: hearts (top-leading), timer (top-trailing), stars (bottom-leading).
final class CombatHUDView: UIView {
    private let config: HudConfig
    private let heartsStack: UIStackView
    private let heartImage: UIImage?
    private let scoreLabel = UILabel()
    private let timerLabel = UILabel()

    init(config: HudConfig, healthCount: Int, starsCount: Int = 0, timerSeconds: Int) {
        self.config = config
        self.heartsStack = Self.makeIconStack(spacing: config.iconSpacing)
        self.heartImage = Self.makeSymbolImage(
            systemName: "heart.fill",
            tint: .systemRed,
            pointSize: config.iconSize
        )
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
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        timerLabel.textAlignment = .right
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.accessibilityIdentifier = "combat.timer"
        // Avoid collapsing to zero width before first layout pass.
        timerLabel.setContentHuggingPriority(.required, for: .horizontal)
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(heartsStack)
        addSubview(timerLabel)
        addSubview(score)

        let margin = CGFloat(config.edgeMargin)
        NSLayoutConstraint.activate([
            heartsStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            heartsStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),

            timerLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            timerLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            score.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
            score.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),
        ])
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

    private static func makeSymbolImage(
        systemName: String,
        tint: UIColor,
        pointSize: Int
    ) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: CGFloat(pointSize), weight: .regular)
        return UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
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
        let starImage = Self.makeSymbolImage(
            systemName: "star.fill",
            tint: .systemOrange,
            pointSize: config.iconSize
        )
        let star = UIImageView(image: starImage)
        star.contentMode = .scaleAspectFit
        star.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            star.widthAnchor.constraint(equalToConstant: size),
            star.heightAnchor.constraint(equalToConstant: size),
        ])

        scoreLabel.text = "\(max(starsCount, 0))"
        scoreLabel.textColor = .white
        scoreLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        scoreLabel.accessibilityIdentifier = "combat.stars"
        scoreLabel.setContentHuggingPriority(.required, for: .horizontal)
        scoreLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        stack.addArrangedSubview(star)
        stack.addArrangedSubview(scoreLabel)
        return stack
    }
}
