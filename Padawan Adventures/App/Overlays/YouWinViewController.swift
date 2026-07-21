import UIKit

final class YouWinViewController: FullscreenOverlayController {
    override func viewDidLoad() {
        super.viewDidLoad()
        addCenteredTitleLabel("You win!")

        let tap = UITapGestureRecognizer(target: self, action: #selector(screenTapped))
        view.addGestureRecognizer(tap)
    }

    @objc private func screenTapped() {
        finish()
    }
}
