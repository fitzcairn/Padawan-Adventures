import UIKit

/// Pit-only HUD: large target word (top-center) + countdown timer (upper-trailing).
/// Solved prefix letters render red; remaining letters stay white.
final class PitHUDView: UIView {
    private let config: HudConfig
    private let wordLabel = UILabel()
    private let timerLabel = UILabel()
    private let wordFont = UIFont.systemFont(ofSize: 44, weight: .bold)

    private var currentWord = ""
    private var solvedCount = 0

    init(config: HudConfig, timerSeconds: Int, word: String = "", solvedCount: Int = 0) {
        self.config = config
        super.init(frame: .zero)
        setup(timerSeconds: timerSeconds, word: word, solvedCount: solvedCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
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

        let margin = CGFloat(config.edgeMargin)
        NSLayoutConstraint.activate([
            wordLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            wordLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            wordLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor,
                constant: margin + 48
            ),
            wordLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: timerLabel.leadingAnchor,
                constant: -12
            ),

            timerLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: margin),
            timerLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -margin),
            timerLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
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
