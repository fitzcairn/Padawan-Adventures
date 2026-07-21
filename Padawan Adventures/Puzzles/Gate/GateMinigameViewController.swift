import UIKit

final class GateMinigameViewController: FullscreenOverlayController {
    override func viewDidLoad() {
        super.viewDidLoad()
        addCenteredPlaceholderButton(
            title: "GATE ENCOUNTERED!!",
            foregroundColor: UIColor(white: 0.1, alpha: 1),
            backgroundColor: UIColor(red: 0.55, green: 0.9, blue: 0.55, alpha: 1),
            action: #selector(gateTapped)
        )
    }

    @objc private func gateTapped() {
        finish()
    }
}
