//
//  GameViewController.swift
//  Padawan Adventures
//

import UIKit
import SpriteKit

final class GameViewController: UIViewController {
    private let world: GameWorld
    private let isoConfig: IsometricConfig
    private let session: AppSession
    private weak var gameScene: GameScene?
    private var isExitingToMenu = false

    init(world: GameWorld, isoConfig: IsometricConfig, session: AppSession) {
        self.world = world
        self.isoConfig = isoConfig
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = SKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let skView = self.view as? SKView else { return }

        let scene = GameScene(
            size: CGSize(width: 1024, height: 768),
            world: world,
            isoConfig: isoConfig,
            saveService: session.saveService
        )
        scene.scaleMode = .aspectFill
        skView.presentScene(scene)
        gameScene = scene

        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true

        installHUD()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    private func installHUD() {
        let hudConfig: HudConfig
        do {
            let loaded = try HudConfig.loadFromBundle()
            try loaded.validate()
            hudConfig = loaded
        } catch {
            hudConfig = .fallback
        }

        let hud = GameHUDView(config: hudConfig)
        hud.onMenuTapped = { [weak self] in
            self?.exitToMenu()
        }
        view.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: view.topAnchor),
            hud.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hud.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @MainActor
    private func exitToMenu() {
        guard !isExitingToMenu else { return }
        isExitingToMenu = true

        Task {
            if let snapshot = gameScene?.currentWorld {
                try? await session.saveService.save(snapshot)
            }
            await session.refreshContinueEligibility()

            let menu = MenuViewController(session: session)
            let nav = UINavigationController(rootViewController: menu)
            nav.setNavigationBarHidden(true, animated: false)

            let window = view.window
                ?? UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)

            window?.rootViewController = nav
            window?.makeKeyAndVisible()
        }
    }
}
