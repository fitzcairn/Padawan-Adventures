import UIKit

final class LevelSelectViewController: LandscapeHostingController {
    private let session: AppSession
    private let levels: [LevelDescriptor]

    private lazy var backButton = AppChrome.makeLargeButton(
        title: "Back",
        action: #selector(backTapped),
        target: self
    )

    init(session: AppSession, levels: [LevelDescriptor]? = nil) {
        self.session = session
        self.levels = levels ?? LevelCatalog.loadFromBundle()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppChrome.backgroundColor

        let levelButtons = levels.enumerated().map { index, level in
            let button = AppChrome.makeLargeButton(
                title: level.displayName,
                action: #selector(levelTapped(_:)),
                target: self
            )
            button.tag = index
            return button
        }

        let levelsStack = UIStackView(arrangedSubviews: levelButtons)
        levelsStack.axis = .horizontal
        levelsStack.spacing = 16
        levelsStack.alignment = .center
        levelsStack.distribution = .fillEqually
        levelsStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(levelsStack)
        view.addSubview(backButton)

        NSLayoutConstraint.activate([
            levelsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            levelsStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            levelsStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor
            ),
            levelsStack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor
            ),

            backButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            backButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    @objc private func levelTapped(_ sender: UIButton) {
        let index = sender.tag
        guard levels.indices.contains(index) else { return }
        let level = levels[index]
        do {
            try session.selectLevel(resourceName: level.resourceName)
        } catch {
            return
        }
        let preparing = PreparingViewController(session: session, mode: .newGame)
        navigationController?.pushViewController(preparing, animated: true)
    }

    @objc private func backTapped() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            let menu = MenuViewController(session: session)
            navigationController?.setViewControllers([menu], animated: true)
        }
    }
}
