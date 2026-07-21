import UIKit

/// Shared base for fullscreen overlays and minigame hosts.
/// Provides dark chrome, a content root that fades in/out, and placeholder helpers.
class FullscreenOverlayController: LandscapeHostingController {
    /// Invoked when the overlay/minigame is ready to dismiss (e.g. placeholder button tap).
    var onFinished: (() -> Void)?

    /// Root for overlay content; faded in on appear and out before dismiss.
    let contentView = UIView()

    static let overlayBackgroundColor = UIColor(white: 0.08, alpha: 1)
    static let contentFadeDuration: TimeInterval = 0.2

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.overlayBackgroundColor

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.alpha = 0
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: Self.contentFadeDuration) {
            self.contentView.alpha = 1
        }
    }

    /// Fades content out, then calls `completion` (used by the shared presenter before dismiss).
    func fadeOutContent(
        duration: TimeInterval = contentFadeDuration,
        completion: @escaping () -> Void
    ) {
        UIView.animate(withDuration: duration, animations: {
            self.contentView.alpha = 0
        }, completion: { _ in
            completion()
        })
    }

    func finish() {
        onFinished?()
    }

    @discardableResult
    func addCenteredPlaceholderButton(
        title: String,
        foregroundColor: UIColor,
        backgroundColor: UIColor,
        action: Selector
    ) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = foregroundColor
        config.baseBackgroundColor = backgroundColor
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28)
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        return button
    }

    @discardableResult
    func addCenteredTitleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 44, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        return label
    }
}
