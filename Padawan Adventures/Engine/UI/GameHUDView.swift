import UIKit

final class GameHUDView: UIView {
    var onMenuTapped: (() -> Void)?

    private let config: HudConfig
    private let menuButton: UIButton
    private let heartsStack: UIStackView
    private let boltsStack: UIStackView

    init(config: HudConfig, healthCount: Int = 0, energyCount: Int = 0) {
        self.config = config
        self.menuButton = Self.makeMenuButton()
        self.heartsStack = Self.makeIconStack(spacing: config.iconSpacing)
        self.boltsStack = Self.makeIconStack(spacing: config.iconSpacing)
        // Trailing-aligned row that grows left as icons are inserted.
        self.boltsStack.semanticContentAttribute = .forceRightToLeft
        super.init(frame: .zero)
        setup(healthCount: healthCount, energyCount: energyCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === menuButton || hit?.isDescendant(of: menuButton) == true {
            return hit
        }
        return nil
    }

    func addHeart() {
        heartsStack.addArrangedSubview(makeIcon(
            systemName: "heart.fill",
            tint: PlaceholderFactory.healthPickupColor
        ))
    }

    func addBolt() {
        boltsStack.addArrangedSubview(makeIcon(
            systemName: "bolt.fill",
            tint: PlaceholderFactory.energyPickupColor
        ))
    }

    private func setup(healthCount: Int, energyCount: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        translatesAutoresizingMaskIntoConstraints = false

        for _ in 0..<max(healthCount, 0) {
            addHeart()
        }
        for _ in 0..<max(energyCount, 0) {
            addBolt()
        }

        let score = makeScoreRow()
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)

        addSubview(heartsStack)
        addSubview(boltsStack)
        addSubview(score)
        addSubview(menuButton)

        let margin = CGFloat(config.edgeMargin)

        NSLayoutConstraint.activate([
            heartsStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            heartsStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),

            boltsStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            boltsStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),

            score.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
            score.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),

            menuButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
            menuButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
        ])
    }

    private func makeIcon(systemName: String, tint: UIColor) -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: systemName))
        imageView.tintColor = tint
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        let size = CGFloat(config.iconSize)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])
        return imageView
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

    private func makeScoreRow() -> UIStackView {
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

        let label = UILabel()
        label.text = "100"
        label.textColor = .white
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false

        stack.addArrangedSubview(star)
        stack.addArrangedSubview(label)
        return stack
    }

    private static func makeMenuButton() -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Menu"
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

    @objc private func menuTapped() {
        onMenuTapped?()
    }
}
