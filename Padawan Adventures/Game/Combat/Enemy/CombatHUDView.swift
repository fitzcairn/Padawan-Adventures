import UIKit

/// Combat-only HUD: health (top-leading), net-progress bar (bottom-leading).
/// The deflect arena opts out of the progress bar — it draws monster HP in-scene instead.
final class CombatHUDView: UIView {
    private let config: HudConfig
    private let heartsStack: UIStackView
    private let heartImage: UIImage?
    private let showsProgressBar: Bool
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var progressFillWidth: NSLayoutConstraint?
    private var progressGoal = 1
    private var displayedProgress: CGFloat = 0
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    private static let progressBarHeight: CGFloat = 17.5
    private static let progressBarWidthFraction: CGFloat = 0.0625

    init(
        config: HudConfig,
        healthCount: Int,
        progress: Int = 0,
        progressGoal: Int = 1,
        showsProgressBar: Bool = true
    ) {
        self.config = config
        self.heartsStack = Self.makeIconStack(spacing: config.iconSpacing)
        self.heartImage = HudVitalIcon.health.makeUIImage(pointSize: CGFloat(config.iconSize))
        self.progressGoal = max(progressGoal, 1)
        self.showsProgressBar = showsProgressBar
        super.init(frame: .zero)
        setup(healthCount: healthCount, progress: progress)
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
        guard showsProgressBar else { return }
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

    private func setup(healthCount: Int, progress: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        // Keep true when hosted by SwiftUI; parent containers may set false + pin edges.
        translatesAutoresizingMaskIntoConstraints = true

        for _ in 0..<max(healthCount, 0) {
            addIcon(image: heartImage, to: heartsStack)
        }

        addSubview(heartsStack)
        let heartsTop = heartsStack.topAnchor.constraint(equalTo: topAnchor)
        let heartsLeading = heartsStack.leadingAnchor.constraint(equalTo: leadingAnchor)
        edgeInsets.addTop(heartsTop)
        edgeInsets.addLeading(heartsLeading)
        NSLayoutConstraint.activate([heartsTop, heartsLeading])

        guard showsProgressBar else {
            edgeInsets.update()
            return
        }

        progressTrack.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        progressTrack.layer.cornerRadius = Self.progressBarHeight * 0.5
        progressTrack.clipsToBounds = true
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.accessibilityIdentifier = "combat.progress"

        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)

        displayedProgress = Self.clampedFraction(current: progress, goal: progressGoal)
        progressFill.backgroundColor = Self.color(forProgress: displayedProgress)
        let fillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        progressFillWidth = fillWidth

        addSubview(progressTrack)

        let progressBottom = progressTrack.bottomAnchor.constraint(equalTo: bottomAnchor)
        let progressLeading = progressTrack.leadingAnchor.constraint(equalTo: leadingAnchor)

        edgeInsets.addBottom(progressBottom)
        edgeInsets.addLeading(progressLeading)

        NSLayoutConstraint.activate([
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
        guard showsProgressBar else { return }
        let trackWidth = progressTrack.bounds.width
        guard trackWidth > 0 else { return }
        let targetWidth = trackWidth * displayedProgress
        let targetColor = Self.color(forProgress: displayedProgress)
        progressFillWidth?.constant = targetWidth
        guard animated else {
            progressFill.backgroundColor = targetColor
            layoutIfNeeded()
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.progressFill.backgroundColor = targetColor
            self.layoutIfNeeded()
        }
    }

    private static func clampedFraction(current: Int, goal: Int) -> CGFloat {
        CGFloat(min(1, max(0, Double(current) / Double(max(goal, 1)))))
    }

    /// Red → orange → yellow → green as the bar fills.
    /// Shared with the deflect arena's in-scene monster HP bar.
    static func color(forProgress progress: CGFloat) -> UIColor {
        let stops: [(CGFloat, UIColor)] = [
            (0, UIColor(red: 0.90, green: 0.18, blue: 0.16, alpha: 1)),
            (1 / 3, UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1)),
            (2 / 3, UIColor(red: 0.98, green: 0.84, blue: 0.12, alpha: 1)),
            (1, UIColor(red: 0.22, green: 0.78, blue: 0.30, alpha: 1)),
        ]
        let t = min(1, max(0, progress))
        for index in 0..<(stops.count - 1) {
            let start = stops[index]
            let end = stops[index + 1]
            if t <= end.0 || index == stops.count - 2 {
                let span = end.0 - start.0
                let local = span > 0 ? (t - start.0) / span : 1
                return lerp(start.1, end.1, CGFloat(min(1, max(0, local))))
            }
        }
        return stops[stops.count - 1].1
    }

    private static func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
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
