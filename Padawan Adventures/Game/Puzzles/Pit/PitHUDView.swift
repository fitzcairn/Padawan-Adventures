import UIKit

/// Pit-only HUD: large target word (top-center) + countdown timer (upper-trailing).
/// Solved prefix letters render red; remaining letters stay white.
final class PitHUDView: UIView {
    private let wordLabel = UILabel()
    private let timerLabel = UILabel()
    private let wordFont = UIFont.systemFont(ofSize: 44, weight: .bold)
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)
    /// Extra clearance so the word does not collide with the timer.
    private var wordLeadingConstraint: NSLayoutConstraint?
    private let wordLeadingExtra: CGFloat = 48

    private var currentWord = ""
    private var solvedCount = 0

    init(config: HudConfig, timerSeconds: Int, word: String = "", solvedCount: Int = 0) {
        super.init(frame: .zero)
        _ = config
        setup(timerSeconds: timerSeconds, word: word, solvedCount: solvedCount)
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
        updateEdgeInsets()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateEdgeInsets()
    }

    func setTimer(seconds: Int, urgent: Bool) {
        timerLabel.text = "\(max(seconds, 0))"
        timerLabel.textColor = urgent ? .systemRed : .white
    }

    func setWord(_ word: String, solvedCount: Int = 0) {
        currentWord = word.lowercased()
        self.solvedCount = max(0, min(solvedCount, currentWord.count))
        wordLabel.attributedText = Self.attributedWord(
            currentWord,
            solvedCount: self.solvedCount,
            font: wordFont
        )
    }

    private func setup(timerSeconds: Int, word: String, solvedCount: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = true

        currentWord = word.lowercased()
        self.solvedCount = max(0, min(solvedCount, currentWord.count))
        wordLabel.attributedText = Self.attributedWord(
            currentWord,
            solvedCount: self.solvedCount,
            font: wordFont
        )
        wordLabel.textAlignment = .center
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        wordLabel.accessibilityIdentifier = "pit.word"
        wordLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        timerLabel.text = "\(max(timerSeconds, 0))"
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        timerLabel.textAlignment = .right
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        timerLabel.accessibilityIdentifier = "pit.timer"
        timerLabel.setContentHuggingPriority(.required, for: .horizontal)
        timerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(wordLabel)
        addSubview(timerLabel)

        let wordTop = wordLabel.topAnchor.constraint(equalTo: topAnchor)
        let wordLeading = wordLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
        let timerTop = timerLabel.topAnchor.constraint(equalTo: topAnchor)
        let timerTrailing = timerLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        wordLeadingConstraint = wordLeading

        edgeInsets.addTop(wordTop)
        edgeInsets.addTop(timerTop)
        edgeInsets.addTrailing(timerTrailing)

        NSLayoutConstraint.activate([
            wordTop,
            wordLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            wordLeading,
            wordLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: timerLabel.leadingAnchor,
                constant: -12
            ),

            timerTop,
            timerTrailing,
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
        updateEdgeInsets()
    }

    private func updateEdgeInsets() {
        edgeInsets.update()
        let insets = ScreenLayout.padding(for: self)
        wordLeadingConstraint?.constant = insets.left + wordLeadingExtra
    }

    private static func attributedWord(
        _ word: String,
        solvedCount: Int,
        font: UIFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: word)
        let fullRange = NSRange(location: 0, length: (word as NSString).length)
        result.addAttributes(
            [
                .font: font,
                .foregroundColor: UIColor.white,
            ],
            range: fullRange
        )
        let redCount = max(0, min(solvedCount, word.count))
        if redCount > 0 {
            result.addAttribute(
                .foregroundColor,
                value: UIColor.systemRed,
                range: NSRange(location: 0, length: redCount)
            )
        }
        return result
    }
}
