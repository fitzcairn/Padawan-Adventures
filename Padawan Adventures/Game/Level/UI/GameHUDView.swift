import UIKit

final class GameHUDView: UIView {
    var onFleeTapped: (() -> Void)?

    private let config: HudConfig
    private let levelName: String
    private let fleeButton: UIButton
    private let heartsStack: UIStackView
    private let boltsStack: UIStackView
    private let heartImage: UIImage?
    private let boltImage: UIImage?
    private let scoreLabel = UILabel()
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    private static let hudIconFadeDuration: TimeInterval = 0.2

    init(
        config: HudConfig,
        levelName: String,
        healthCount: Int = 0,
        energyCount: Int = 0,
        starsCount: Int = 0
    ) {
        self.config = config
        self.levelName = levelName
        self.fleeButton = Self.makeFleeButton()
        self.heartsStack = Self.makeIconStack(spacing: config.iconSpacing)
        self.boltsStack = Self.makeIconStack(spacing: config.iconSpacing)
        // Trailing-aligned row that grows left as icons are inserted.
        self.boltsStack.semanticContentAttribute = .forceRightToLeft
        self.heartImage = Self.makeSymbolImage(
            systemName: "heart.fill",
            tint: .systemRed,
            pointSize: config.iconSize
        )
        self.boltImage = Self.makeSymbolImage(
            systemName: "bolt.fill",
            tint: .systemYellow,
            pointSize: config.iconSize
        )
        super.init(frame: .zero)
        setup(healthCount: healthCount, energyCount: energyCount, starsCount: starsCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === fleeButton || hit?.isDescendant(of: fleeButton) == true {
            return hit
        }
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeInsets.update()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        edgeInsets.update()
    }

    func addHeart() {
        addIcon(image: heartImage, to: heartsStack, animated: true)
    }

    func addBolt() {
        addIcon(image: boltImage, to: boltsStack, animated: true)
    }

    func removeHeart() {
        removeIcon(from: heartsStack, animated: true)
    }

    func removeBolt() {
        removeIcon(from: boltsStack, animated: true)
    }

    func setVitals(health: Int, energy: Int) {
        clearIcons(in: heartsStack)
        clearIcons(in: boltsStack)
        for _ in 0..<max(health, 0) {
            addIcon(image: heartImage, to: heartsStack, animated: false)
        }
        for _ in 0..<max(energy, 0) {
            addIcon(image: boltImage, to: boltsStack, animated: false)
        }
    }

    func setStars(_ count: Int) {
        scoreLabel.text = "\(max(count, 0))"
    }

    private func setup(healthCount: Int, energyCount: Int, starsCount: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<max(healthCount, 0) {
            addIcon(image: heartImage, to: heartsStack, animated: false)
        }
        for _ in 0..<max(energyCount, 0) {
            addIcon(image: boltImage, to: boltsStack, animated: false)
        }

        let score = makeScoreRow(starsCount: starsCount)
        let levelLabel = makeLevelNameLabel()
        fleeButton.addTarget(self, action: #selector(fleeTapped), for: .touchUpInside)

        addSubview(heartsStack)
        addSubview(boltsStack)
        addSubview(score)
        addSubview(levelLabel)
        addSubview(fleeButton)

        let heartsTop = heartsStack.topAnchor.constraint(equalTo: topAnchor)
        let heartsLeading = heartsStack.leadingAnchor.constraint(equalTo: leadingAnchor)
        let boltsTop = boltsStack.topAnchor.constraint(equalTo: topAnchor)
        let boltsTrailing = boltsStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        let scoreBottom = score.bottomAnchor.constraint(equalTo: bottomAnchor)
        let scoreLeading = score.leadingAnchor.constraint(equalTo: leadingAnchor)
        let levelBottom = levelLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        let fleeBottom = fleeButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        let fleeTrailing = fleeButton.trailingAnchor.constraint(equalTo: trailingAnchor)

        edgeInsets.addTop(heartsTop)
        edgeInsets.addLeading(heartsLeading)
        edgeInsets.addTop(boltsTop)
        edgeInsets.addTrailing(boltsTrailing)
        edgeInsets.addBottom(scoreBottom)
        edgeInsets.addLeading(scoreLeading)
        edgeInsets.addBottom(levelBottom)
        edgeInsets.addBottom(fleeBottom)
        edgeInsets.addTrailing(fleeTrailing)

        NSLayoutConstraint.activate([
            heartsTop,
            heartsLeading,

            boltsTop,
            boltsTrailing,

            scoreBottom,
            scoreLeading,

            levelLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            levelBottom,
            levelLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: score.trailingAnchor,
                constant: 8
            ),
            levelLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: fleeButton.leadingAnchor,
                constant: -8
            ),

            fleeBottom,
            fleeTrailing,
        ])
        edgeInsets.update()
    }

    private func addIcon(image: UIImage?, to stack: UIStackView, animated: Bool) {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        let size = CGFloat(config.iconSize)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])

        imageView.alpha = animated ? 0 : 1
        // Avoid UIStackView's implicit layout animation fighting SpriteKit's frame.
        UIView.performWithoutAnimation {
            stack.addArrangedSubview(imageView)
            stack.layoutIfNeeded()
        }

        guard animated else { return }
        UIView.animate(
            withDuration: Self.hudIconFadeDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            imageView.alpha = 1
        }
    }

    private func removeIcon(from stack: UIStackView, animated: Bool) {
        guard let icon = stack.arrangedSubviews.last else { return }
        let remove = {
            UIView.performWithoutAnimation {
                stack.removeArrangedSubview(icon)
                icon.removeFromSuperview()
                stack.layoutIfNeeded()
            }
        }
        guard animated else {
            remove()
            return
        }
        UIView.animate(
            withDuration: Self.hudIconFadeDuration,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction],
            animations: { icon.alpha = 0 },
            completion: { _ in remove() }
        )
    }

    private func clearIcons(in stack: UIStackView) {
        UIView.performWithoutAnimation {
            for view in stack.arrangedSubviews {
                stack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            stack.layoutIfNeeded()
        }
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
        stack.isUserInteractionEnabled = false
        return stack
    }

    private func makeScoreRow(starsCount: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(config.scoreTextGap)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false

        let size = CGFloat(config.iconSize)
        let star = UIImageView(image: UIImage(systemName: "star.fill"))
        star.tintColor = .systemOrange
        star.contentMode = .scaleAspectFit
        star.translatesAutoresizingMaskIntoConstraints = false
        star.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            star.widthAnchor.constraint(equalToConstant: size),
            star.heightAnchor.constraint(equalToConstant: size),
        ])

        scoreLabel.text = "\(max(starsCount, 0))"
        scoreLabel.textColor = .white
        scoreLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        scoreLabel.isUserInteractionEnabled = false

        stack.addArrangedSubview(star)
        stack.addArrangedSubview(scoreLabel)
        return stack
    }

    private func makeLevelNameLabel() -> UILabel {
        let label = UILabel()
        label.text = levelName
        label.textColor = .systemGreen
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        return label
    }

    private static func makeFleeButton() -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Flee the planet!"
        configuration.baseForegroundColor = .black
        configuration.baseBackgroundColor = UIColor(white: 0.92, alpha: 1)
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 17, weight: .semibold)
            return outgoing
        }

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func fleeTapped() {
        onFleeTapped?()
    }
}
