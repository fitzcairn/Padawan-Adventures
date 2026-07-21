//
//  GameViewController.swift
//  Padawan Adventures
//

import UIKit
import SpriteKit

final class GameViewController: LandscapeHostingController {
    private let world: GameWorld
    private let isoConfig: IsometricConfig
    private let session: AppSession
    private weak var gameScene: GameScene?
    private weak var hud: GameHUDView?
    private var isExitingToMenu = false
    private var isPresentingFight = false
    private var isPresentingPit = false
    private var isPresentingWin = false

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
            enemyConfig: session.enemyConfig,
            saveService: session.saveService
        )
        scene.scaleMode = .aspectFill
        scene.onEnemyContact = { [weak self] enemyID in
            self?.presentEnemyFight(enemyID: enemyID)
        }
        scene.onPitEntered = { [weak self] in
            self?.presentPit()
        }
        scene.onPickupCollected = { [weak self] kind in
            self?.handlePickupCollected(kind)
        }
        scene.onTreasureCollected = { [weak self] in
            self?.presentYouWin()
        }
        skView.presentScene(scene)
        gameScene = scene

        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true

        installHUD()
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

        let hud = GameHUDView(
            config: hudConfig,
            healthCount: world.healthCount,
            energyCount: world.energyCount
        )
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
        self.hud = hud
    }

    private func handlePickupCollected(_ kind: PickupKind) {
        switch kind {
        case .health:
            hud?.addHeart()
        case .energy:
            hud?.addBolt()
        case .treasure:
            break
        }
    }

    @MainActor
    private func presentEnemyFight(enemyID: UUID) {
        guard !isPresentingFight else { return }
        isPresentingFight = true

        gameScene?.fadeSimulationOut { [weak self] in
            guard let self else { return }
            let fight = EnemyFightViewController()
            fight.modalPresentationStyle = .fullScreen
            fight.onFightTapped = { [weak self, weak fight] in
                guard let self else { return }
                fight?.dismiss(animated: false) {
                    self.gameScene?.resolveEnemyEncounter(enemyID: enemyID) {
                        self.isPresentingFight = false
                    }
                }
            }
            self.present(fight, animated: false)
        }
    }

    @MainActor
    private func presentPit() {
        guard !isPresentingPit else { return }
        isPresentingPit = true

        let pit = PitViewController()
        pit.modalPresentationStyle = .fullScreen
        pit.onPitTapped = { [weak self, weak pit] in
            guard let self else { return }
            pit?.dismiss(animated: false) {
                self.gameScene?.resolvePitEncounter()
                self.isPresentingPit = false
            }
        }
        present(pit, animated: false)
    }

    @MainActor
    private func presentYouWin() {
        guard !isPresentingWin else { return }
        isPresentingWin = true

        let win = YouWinViewController()
        win.modalPresentationStyle = .fullScreen
        win.onScreenTapped = { [weak self, weak win] in
            guard let self else { return }
            win?.dismiss(animated: false) {
                self.exitToMenu()
            }
        }
        present(win, animated: false)
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
            let nav = LandscapeNavigationController(rootViewController: menu)
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
