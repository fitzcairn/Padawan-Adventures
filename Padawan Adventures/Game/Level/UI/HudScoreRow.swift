import UIKit

extension GameHUDView {
    func makeScoreRow(starsCount: Int) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = CGFloat(config.scoreTextGap)
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        stack.clipsToBounds = false

        let size = CGFloat(config.iconSize)
        coinHost.translatesAutoresizingMaskIntoConstraints = false
        coinHost.isUserInteractionEnabled = false
        coinHost.clipsToBounds = false
        if coinImageView.superview !== coinHost {
            coinHost.addSubview(coinImageView)
            NSLayoutConstraint.activate([
                coinHost.widthAnchor.constraint(equalToConstant: size),
                coinHost.heightAnchor.constraint(equalToConstant: size),
                coinImageView.centerXAnchor.constraint(equalTo: coinHost.centerXAnchor),
                coinImageView.centerYAnchor.constraint(equalTo: coinHost.centerYAnchor),
            ])
        }

        scoreLabel.text = "\(max(starsCount, 0))"
        scoreLabel.textColor = .white
        scoreLabel.font = AppFont.uiKit(size: 22, weight: .semibold)
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        scoreLabel.isUserInteractionEnabled = false
        scoreLabel.applyAppCopyShadow()

        stack.addArrangedSubview(coinHost)
        stack.addArrangedSubview(scoreLabel)
        return stack
    }
}
