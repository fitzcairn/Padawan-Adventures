import UIKit

final class GameHUDView: UIView {
    var onMenuTapped: (() -> Void)?

    private let config: HudConfig
    private let menuButton: UIButton

    init(config: HudConfig) {
        self.config = config
        self.menuButton = Self.makeMenuButton()
        super.init(frame: .zero)
        setup()
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

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true
        translatesAutoresizingMaskIntoConstraints = false

        let hearts = makeIconRow(
            systemName: "heart.fill",
            tint: .systemRed,
            count: 3
        )
        let bolts = makeIconRow(
            systemName: "bolt.fill",
            tint: .systemYellow,
            count: 3
        )
        let score = makeScoreRow()

        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)

        addSubview(hearts)
        addSubview(bolts)
        addSubview(score)
        addSubview(menuButton)

        let margin = CGFloat(config.edgeMargin)

        NSLayoutConstraint.activate([
            hearts.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            hearts.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),

            bolts.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            bolts.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),

            score.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
            score.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: margin),

            menuButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -margin),
            menuButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
        ])
    }

    private func makeIconRow(systemName: String, tint: UIColor, count: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(config.iconSpacing)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false

        let size = CGFloat(config.iconSize)
        for _ in 0..<count {
            let imageView = UIImageView(image: UIImage(systemName: systemName))
            imageView.tintColor = tint
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.isUserInteractionEnabled = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: size),
                imageView.heightAnchor.constraint(equalToConstant: size),
            ])
            stack.addArrangedSubview(imageView)
        }
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
