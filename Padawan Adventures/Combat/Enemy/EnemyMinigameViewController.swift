import UIKit

final class EnemyMinigameViewController: FullscreenOverlayController {
    override func viewDidLoad() {
        super.viewDidLoad()
        addCenteredPlaceholderButton(
            title: "Enemy fight!",
            foregroundColor: .white,
            backgroundColor: UIColor(red: 0.75, green: 0.15, blue: 0.15, alpha: 1),
            action: #selector(fightTapped)
        )
    }

    @objc private func fightTapped() {
        finish()
    }
}
