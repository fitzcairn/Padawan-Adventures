import UIKit

final class BoomViewController: LandscapeHostingController {
    var onBoomTapped: (() -> Void)?

    private let boomButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "BOOM!"
        config.baseForegroundColor = UIColor(white: 0.15, alpha: 1)
        config.baseBackgroundColor = UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 1)
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28)
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        view.addSubview(boomButton)
        boomButton.addTarget(self, action: #selector(boomTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            boomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            boomButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func boomTapped() {
        onBoomTapped?()
    }
}
