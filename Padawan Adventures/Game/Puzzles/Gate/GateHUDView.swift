import UIKit

/// Gate-only HUD: large target word (top-center).
/// Connected prefix letters render red; remaining letters stay white.
final class GateHUDView: UIView {
    private let wordLabel = UILabel()
    private let wordFont = AppFont.uiKit(size: 44, weight: .bold)
    private lazy var edgeInsets = ScreenEdgeInsetController(host: self)

    private var currentWord = ""
    private var connectedCount = 0

    init(config: HudConfig, word: String = "", connectedCount: Int = 0) {
        super.init(frame: .zero)
        _ = config
        setup(word: word, connectedCount: connectedCount)
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

    func setWord(_ word: String, connectedCount: Int = 0) {
        currentWord = word.lowercased()
        self.connectedCount = max(0, min(connectedCount, currentWord.count))
        wordLabel.attributedText = Self.attributedWord(
            currentWord,
            connectedCount: self.connectedCount,
            font: wordFont
        )
    }

    private func setup(word: String, connectedCount: Int) {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        translatesAutoresizingMaskIntoConstraints = true

        currentWord = word.lowercased()
        self.connectedCount = max(0, min(connectedCount, currentWord.count))
        wordLabel.attributedText = Self.attributedWord(
            currentWord,
            connectedCount: self.connectedCount,
            font: wordFont
        )
        wordLabel.textAlignment = .center
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        wordLabel.applyAppCopyShadow()
        wordLabel.accessibilityIdentifier = "gate.word"
        wordLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(wordLabel)

        let wordTop = wordLabel.topAnchor.constraint(equalTo: topAnchor)
        let wordLeading = wordLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
        let wordTrailing = wordLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)

        edgeInsets.addTop(wordTop)
        edgeInsets.addLeading(wordLeading)
        edgeInsets.addTrailing(wordTrailing)

        NSLayoutConstraint.activate([
            wordTop,
            wordLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            wordLeading,
            wordTrailing,
        ])
        updateEdgeInsets()
    }

    private func updateEdgeInsets() {
        edgeInsets.update()
    }

    private static func attributedWord(
        _ word: String,
        connectedCount: Int,
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
        let redCount = max(0, min(connectedCount, word.count))
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
