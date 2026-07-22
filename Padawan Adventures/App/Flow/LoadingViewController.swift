import UIKit

final class LoadingViewController: LandscapeHostingController {
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
        Task { await loadAndPresentPlayerSelect() }
    }

    @MainActor
    private func loadAndPresentPlayerSelect() async {
        let session = await AppSession.loadResources()
        let playerSelect = PlayerSelectViewController(session: session)
        navigationController?.setViewControllers([playerSelect], animated: false)
    }
}
