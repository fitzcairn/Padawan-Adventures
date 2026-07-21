import UIKit

final class NewGameStartViewController: UIViewController {
    private let session: AppSession

    private lazy var startButton = AppChrome.makeLargeButton(
        title: "start!",
        action: #selector(startTapped),
        target: self
    )

    init(session: AppSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppChrome.backgroundColor
        view.addSubview(startButton)

        NSLayoutConstraint.activate([
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            startButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    @objc private func startTapped() {
        let preparing = PreparingViewController(session: session, mode: .newGame)
        navigationController?.pushViewController(preparing, animated: true)
    }
}
