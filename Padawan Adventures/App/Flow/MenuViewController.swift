import UIKit

final class MenuViewController: LandscapeHostingController {
    private let session: AppSession

    private lazy var continueButton = AppChrome.makeLargeButton(
        title: "CONTINUE",
        action: #selector(continueTapped),
        target: self
    )
    private lazy var newGameButton = AppChrome.makeLargeButton(
        title: "NEW GAME",
        action: #selector(newGameTapped),
        target: self
    )
    private lazy var leaderboardButton = AppChrome.makeLargeButton(
        title: "LEADERBOARD",
        action: #selector(leaderboardTapped),
        target: self
    )
    private lazy var quitButton = AppChrome.makeLargeButton(
        title: "QUIT",
        action: #selector(quitTapped),
        target: self
    )
    private let versionLabel = AppChrome.makeCenteredLabel("", size: 13, weight: .regular)

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

        versionLabel.text = AppChrome.versionBuildString
        versionLabel.textColor = AppChrome.secondaryTextColor

        let stack = UIStackView(arrangedSubviews: [
            continueButton,
            newGameButton,
            leaderboardButton,
            quitButton,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        view.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 320),

            versionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        refreshContinueVisibility()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task {
            await session.refreshContinueEligibility()
            refreshContinueVisibility()
        }
    }

    private func refreshContinueVisibility() {
        continueButton.isHidden = !session.hasCompatibleSave
    }

    @objc private func continueTapped() {
        let preparing = PreparingViewController(session: session, mode: .continueSave)
        navigationController?.pushViewController(preparing, animated: true)
    }

    @objc private func newGameTapped() {
        let levelSelect = LevelSelectViewController(session: session)
        navigationController?.pushViewController(levelSelect, animated: true)
    }

    @objc private func leaderboardTapped() {
        // Intentionally no-op for now.
    }

    @objc private func quitTapped() {
        exit(0)
    }
}
