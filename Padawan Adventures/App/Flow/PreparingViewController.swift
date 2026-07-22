import UIKit

final class PreparingViewController: LandscapeHostingController {
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

    @MainActor
    private func prepareAndPresentGame() async {
        if mode == .continueSave, let lastLevel = session.playerState?.lastLevelStarted {
            try? session.selectLevel(resourceName: lastLevel)
        }

        if let resourceName = session.selectedLevelResourceName {
            await session.markLevelStarted(resourceName: resourceName)
        }

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
        let playerConfig = session.playerConfig
        let enemyConfig = session.enemyConfig
        let health = session.playerState?.health ?? playerConfig.startingHealth
        let energy = session.playerState?.energy ?? playerConfig.startingEnergy

        do {
            var world = try await Task.detached(priority: .userInitiated) {
                try ProceduralGenerator().generate(
                    from: config,
                    playerConfig: playerConfig,
                    enemyConfig: enemyConfig
                )
            }.value
            world.healthCount = health
            world.energyCount = energy
            return world
        } catch {
            let fallback = AppSession.fallbackConfig()
            do {
                var world = try await Task.detached(priority: .userInitiated) {
                    try ProceduralGenerator().generate(
                        from: fallback,
                        playerConfig: .fallback,
                        enemyConfig: .fallback
                    )
                }.value
                world.healthCount = health
                world.energyCount = energy
                return world
            } catch {
                return Self.minimalWorld(health: health, energy: energy, playerConfig: playerConfig)
            }
        }
    }

    private static func minimalWorld(
        health: Int,
        energy: Int,
        playerConfig: PlayerConfig
    ) -> GameWorld {
        GameWorld(
            width: 1,
            height: 1,
            storyCount: 1,
            tiles: [[[Tile(kind: .floor(isPit: false))]]],
            entities: [
                GameEntity(
                    letter: playerConfig.letter.first ?? "P",
                    position: GridCoord(x: 0, y: 0, story: 0),
                    isPlayer: true
                ),
            ],
            spawn: GridCoord(x: 0, y: 0, story: 0),
            healthCount: health,
            energyCount: energy
        )
    }
}
