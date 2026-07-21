import UIKit

final class EnemyFightViewController: UIViewController {
    var onFightTapped: (() -> Void)?

    private let fightButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Enemy fight!"
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1)
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28)
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        view.addSubview(fightButton)
        fightButton.addTarget(self, action: #selector(fightTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            fightButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            fightButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    @objc private func fightTapped() {
        onFightTapped?()
    }
}
