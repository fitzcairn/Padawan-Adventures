import UIKit

/// Combat-only HUD: health (top-leading), timer (top-trailing), net-progress bar (bottom-leading).
final class CombatHUDView: UIView {
    private let config: HudConfig
    private let heartsStack: UIStackView
    private let heartImage: UIImage?
    private let timerLabel = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var progressFillWidth: NSLayoutConstraint?
    private var progressGoal = 1
    private var displayedProgress: CGFloat = 0
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    private static let progressBarHeight: CGFloat = 14
    private static let progressBarWidthFraction: CGFloat = 0.05

    init(config: HudConfig, healthCount: Int, progress: Int = 0, progressGoal: Int = 1, timerSeconds: Int) {
        self.config = config
        self.heartsStack = Self.makeIconStack(spacing: config.iconSpacing)
        self.heartImage = HudVitalIcon.health.makeUIImage(pointSize: CGFloat(config.iconSize))
        self.progressGoal = max(progressGoal, 1)
        super.init(frame: .zero)
        setup(healthCount: healthCount, progress: progress, timerSeconds: timerSeconds)
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
        applyProgressFill(animated: false)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        edgeInsets.update()
    }

    func setProgress(current: Int, goal: Int) {
        progressGoal = max(goal, 1)
        let target = Self.clampedFraction(current: current, goal: progressGoal)
        guard abs(target - displayedProgress) > 0.000_1 else { return }
        displayedProgress = target
        applyProgressFill(animated: true)
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

    private func setup(healthCount: Int, progress: Int, timerSeconds: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        // Keep true when hosted by SwiftUI; parent containers may set false + pin edges.
        translatesAutoresizingMaskIntoConstraints = true

        for _ in 0..<max(healthCount, 0) {
            addIcon(image: heartImage, to: heartsStack)
        }

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
        timerLabel.isHidden = !HudConfig.showsMinigameTimer

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        progressTrack.layer.cornerRadius = Self.progressBarHeight * 0.5
        progressTrack.clipsToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.accessibilityIdentifier = "combat.progress"

        progressFill.backgroundColor = UIColor.systemGreen
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)

        displayedProgress = Self.clampedFraction(current: progress, goal: progressGoal)
        let fillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidth = fillWidth

        addSubview(heartsStack)
        addSubview(timerLabel)
        addSubview(progressTrack)

        let heartsTop = heartsStack.topAnchor.constraint(equalTo: topAnchor)
        let heartsLeading = heartsStack.leadingAnchor.constraint(equalTo: leadingAnchor)
        let timerTop = timerLabel.topAnchor.constraint(equalTo: topAnchor)
        let timerTrailing = timerLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        let progressBottom = progressTrack.bottomAnchor.constraint(equalTo: bottomAnchor)
        let progressLeading = progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor)

        edgeInsets.addTop(heartsTop)
        edgeInsets.addLeading(heartsLeading)
        edgeInsets.addTop(timerTop)
        edgeInsets.addTrailing(timerTrailing)
        edgeInsets.addBottom(progressBottom)
        edgeInsets.addLeading(progressLeading)

        NSLayoutConstraint.activate([
            heartsTop,
            heartsLeading,

            timerTop,
            timerTrailing,
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            progressBottom,
            progressLeading,
            progressTrack.widthAnchor.constraint(
                equalTo: widthAnchor,
                multiplier: Self.progressBarWidthFraction
            ),
            progressTrack.heightAnchor.constraint(equalToConstant: Self.progressBarHeight),

            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            fillWidth,
        ])
        edgeInsets.update()
    }

    private func applyProgressFill(animated: Bool) {
        let trackWidth = progressTrack.bounds.width
        guard trackWidth > 0 else { return }
        let targetWidth = trackWidth * displayedProgress
        progressFillWidth?.constant = targetWidth
        guard animated else {
            layoutIfNeeded()
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.layoutIfNeeded()
        }
    }

    private static func clampedFraction(current: Int, goal: Int) -> CGFloat {
        CGFloat(min(1, max(0, Double(current) / Double(max(goal, 1)))))
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
}
