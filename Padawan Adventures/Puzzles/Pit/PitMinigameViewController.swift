import UIKit

final class PitMinigameViewController: FullscreenOverlayController {
    override func viewDidLoad() {
        super.viewDidLoad()
        addCenteredPlaceholderButton(
            title: "PIT!",
            foregroundColor: .white,
            backgroundColor: UIColor(red: 0.55, green: 0.25, blue: 0.1, alpha: 1),
            action: #selector(pitTapped)
        )
    }

    @objc private func pitTapped() {
        finish()
    }
}
