import UIKit

final class PreparingViewController: UIViewController {
    private let session: AppSession
    private let mode: GameLaunchMode
    private let statusLabel = AppChrome.makeCenteredLabel(
        "PREPARING FOR TAKEOFF...",
        size: 28,
        weight: .semibold
    )
    private var didStartLoad = false

    init(session: AppSession, mode: GameLaunchMode) {
        self.session = session
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
        guard !didStartLoad else { return }
        didStartLoad = true
        Task { await prepareAndPresentGame() }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    @MainActor
    private func prepareAndPresentGame() async {
        let world = await loadWorld()
        let isoConfig = session.seedConfig.display.makeIsometricConfig()
        let game = GameViewController(
            world: world,
            isoConfig: isoConfig,
            session: session
        )

        // Replace root so the player cannot navigate back into preparing/menu.
        let window = view.window
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)

        window?.rootViewController = game
        window?.makeKeyAndVisible()
    }

    private func loadWorld() async -> GameWorld {
        switch mode {
        case .continueSave:
            if let saved = try? await session.saveService.load(),
               WorldLoader.isCompatibleSave(saved, with: session.seedConfig) {
                return saved
            }
            return await generateWorld()

        case .newGame:
            try? await session.saveService.delete()
            return await generateWorld()
        }
    }

    private func generateWorld() async -> GameWorld {
        let config = session.seedConfig
        let enemyConfig = session.enemyConfig
        do {
            return try await Task.detached(priority: .userInitiated) {
                try ProceduralGenerator().generate(from: config, enemyConfig: enemyConfig)
            }.value
        } catch {
            let fallback = AppSession.fallbackConfig()
            return (try? await Task.detached(priority: .userInitiated) {
                try ProceduralGenerator().generate(from: fallback, enemyConfig: .fallback)
            }.value) ?? Self.minimalWorld()
        }
    }

    private static func minimalWorld() -> GameWorld {
        GameWorld(
            width: 1,
            height: 1,
            storyCount: 1,
            tiles: [[[Tile(kind: .floor(isPit: false))]]],
            entities: [GameEntity(letter: "P", position: GridCoord(x: 0, y: 0, story: 0), isPlayer: true)],
            spawn: GridCoord(x: 0, y: 0, story: 0)
        )
    }
}
