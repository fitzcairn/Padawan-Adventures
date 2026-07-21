import UIKit

final class GateEncounterViewController: LandscapeHostingController {
    var onGateTapped: (() -> Void)?

    private let gateButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "GATE ENCOUNTERED!!"
        config.baseForegroundColor = UIColor(white: 0.1, alpha: 1)
        config.baseBackgroundColor = UIColor(red: 0.55, green: 0.9, blue: 0.55, alpha: 1)
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28)
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        view.addSubview(gateButton)
        gateButton.addTarget(self, action: #selector(gateTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            gateButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            gateButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func gateTapped() {
        onGateTapped?()
    }
}
