import UIKit

final class DestructibleWallMinigameViewController: FullscreenOverlayController {
    override func viewDidLoad() {
        super.viewDidLoad()
        addCenteredPlaceholderButton(
            title: "BOOM!",
            foregroundColor: UIColor(white: 0.15, alpha: 1),
            backgroundColor: UIColor(red: 1.0, green: 0.92, blue: 0.45, alpha: 1),
            action: #selector(boomTapped)
        )
    }

    @objc private func boomTapped() {
        finish()
    }
}
