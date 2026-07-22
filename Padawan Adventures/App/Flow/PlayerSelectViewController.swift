import UIKit

final class PlayerSelectViewController: LandscapeHostingController {
    private let session: AppSession
    private var playerNames: [String] = []

    private let titleLabel = AppChrome.makeCenteredLabel("Select Player", size: 28, weight: .semibold)
    private let scrollView = UIScrollView()
    private let listStack = UIStackView()
    private lazy var newButton = AppChrome.makeLargeButton(
        title: "New",
        action: #selector(newTapped),
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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = true

        listStack.axis = .vertical
        listStack.spacing = 12
        listStack.alignment = .fill
        listStack.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(scrollView)
        view.addSubview(newButton)
        scrollView.addSubview(listStack)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scrollView.widthAnchor.constraint(equalToConstant: 360),
            scrollView.bottomAnchor.constraint(equalTo: newButton.topAnchor, constant: -16),

            listStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            listStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            newButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            ),
            newButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reloadPlayers() }
    }

    @MainActor
    private func reloadPlayers() async {
        playerNames = (try? await session.playerStore.listPlayers()) ?? []
        rebuildList()
    }

    private func rebuildList() {
        listStack.arrangedSubviews.forEach { view in
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if playerNames.isEmpty {
            let empty = AppChrome.makeCenteredLabel(
                "No players yet. Tap New to create one.",
                size: 16,
                weight: .regular
            )
            empty.textColor = AppChrome.secondaryTextColor
            empty.numberOfLines = 0
            listStack.addArrangedSubview(empty)
            return
        }

        for (index, name) in playerNames.enumerated() {
            listStack.addArrangedSubview(makePlayerRow(name: name, index: index))
        }
    }

    private func makePlayerRow(name: String, index: Int) -> UIView {
        let nameButton = UIButton(type: .system)
        var nameConfig = UIButton.Configuration.filled()
        nameConfig.title = name
        nameConfig.baseForegroundColor = .black
        nameConfig.baseBackgroundColor = UIColor(white: 0.92, alpha: 1)
        nameConfig.cornerStyle = .medium
        nameConfig.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        nameConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = .systemFont(ofSize: 20, weight: .semibold)
            return outgoing
        }
        nameButton.configuration = nameConfig
        nameButton.tag = index
        nameButton.addTarget(self, action: #selector(playerTapped(_:)), for: .touchUpInside)
        nameButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let trashButton = UIButton(type: .system)
        let trashImage = UIImage(systemName: "trash")
        trashButton.setImage(trashImage, for: .normal)
        trashButton.tintColor = UIColor(white: 0.85, alpha: 1)
        trashButton.tag = index
        trashButton.addTarget(self, action: #selector(deleteTapped(_:)), for: .touchUpInside)
        trashButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            trashButton.widthAnchor.constraint(equalToConstant: 44),
            trashButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        let row = UIStackView(arrangedSubviews: [nameButton, trashButton])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        return row
    }

    @objc private func playerTapped(_ sender: UIButton) {
        let index = sender.tag
        guard playerNames.indices.contains(index) else { return }
        let name = playerNames[index]
        Task { await selectPlayer(named: name) }
    }

    @objc private func deleteTapped(_ sender: UIButton) {
        let index = sender.tag
        guard playerNames.indices.contains(index) else { return }
        let name = playerNames[index]
        confirmDelete(playerName: name)
    }

    @objc private func newTapped() {
        presentNameAlert(prefill: nil)
    }

    private func confirmDelete(playerName: String) {
        let alert = UIAlertController(
            title: "Delete Player",
            message: "Delete \"\(playerName)\" and all saved progress? This cannot be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            Task { await self?.deletePlayer(named: playerName) }
        })
        present(alert, animated: true)
    }

    private func presentNameAlert(prefill: String?) {
        let alert = UIAlertController(
            title: "New Player",
            message: "Enter a unique player name.",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Player name"
            textField.autocapitalizationType = .words
            textField.text = prefill
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            let raw = alert.textFields?.first?.text ?? ""
            Task { await self?.createPlayer(named: raw) }
        })
        present(alert, animated: true)
    }

    private func presentDuplicateNameError(attemptedName: String) {
        let alert = UIAlertController(
            title: "Name Already Taken",
            message: "Player names must be unique. Choose a different name.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.presentNameAlert(prefill: attemptedName)
        })
        present(alert, animated: true)
    }

    @MainActor
    private func selectPlayer(named name: String) async {
        do {
            try await session.bindPlayer(name: name)
            goToMenu()
        } catch {
            // Ignore bind failures for missing/corrupt state; list refresh will reflect disk.
            await reloadPlayers()
        }
    }

    @MainActor
    private func createPlayer(named name: String) async {
        let trimmed = PlayerStateStore.normalizedName(name)
        guard !trimmed.isEmpty else {
            presentNameAlert(prefill: nil)
            return
        }

        do {
            try await session.createAndBindPlayer(name: trimmed)
            goToMenu()
        } catch PlayerStateError.nameNotUnique {
            presentDuplicateNameError(attemptedName: trimmed)
        } catch {
            presentNameAlert(prefill: trimmed)
        }
    }

    @MainActor
    private func deletePlayer(named name: String) async {
        try? await session.deletePlayer(name: name)
        await reloadPlayers()
    }

    private func goToMenu() {
        let menu = MenuViewController(session: session)
        navigationController?.setViewControllers([menu], animated: true)
    }
}
