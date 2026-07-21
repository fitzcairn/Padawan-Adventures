import UIKit

final class LoadingViewController: UIViewController {
    private let statusLabel = AppChrome.makeCenteredLabel("Loading...", size: 32, weight: .semibold)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppChrome.backgroundColor
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await loadAndPresentMenu() }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    @MainActor
    private func loadAndPresentMenu() async {
        let session = await AppSession.loadResources()
        let menu = MenuViewController(session: session)
        navigationController?.setViewControllers([menu], animated: false)
    }
}
