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
    private var isExitingToLevelSelect = false
    private lazy var overlayPresenter = FullscreenOverlayPresenter(
        host: self,
        fadeWorldOut: { [weak self] completion in
            if let scene = self?.gameScene {
                scene.fadeSimulationOut(completion: completion)
            } else {
                completion()
            }
        }
    )

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
        // Avoid `self.view` here (re-enters loadView). Prefer an active window scene's screen.
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        view = SKView(frame: windowScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 1024, height: 768))
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
        scene.onBoomEntered = { [weak self] coord in
            self?.presentDestructibleWall(at: coord)
        }
        scene.onGateEntered = { [weak self] coord in
            self?.presentGate(at: coord)
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
            levelName: session.selectedLevelName,
            healthCount: world.healthCount,
            energyCount: world.energyCount
        )
        hud.onFleeTapped = { [weak self] in
            self?.exitToLevelSelect()
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
        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: { EnemyMinigameViewController() },
            onResolved: { [weak self] done in
                guard let scene = self?.gameScene else {
                    done()
                    return
                }
                scene.resolveEnemyEncounter(enemyID: enemyID, completion: done)
            }
        )
    }

    @MainActor
    private func presentPit() {
        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: { PitMinigameViewController() },
            onResolved: { [weak self] done in
                guard let scene = self?.gameScene else {
                    done()
                    return
                }
                scene.resolvePitEncounter(completion: done)
            }
        )
    }

    @MainActor
    private func presentDestructibleWall(at coord: GridCoord) {
        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: { DestructibleWallMinigameViewController() },
            onResolved: { [weak self] done in
                guard let scene = self?.gameScene else {
                    done()
                    return
                }
                scene.resolveBoomEncounter(at: coord, completion: done)
            }
        )
    }

    @MainActor
    private func presentGate(at coord: GridCoord) {
        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: { GateMinigameViewController() },
            onResolved: { [weak self] done in
                guard let scene = self?.gameScene else {
                    done()
                    return
                }
                scene.resolveGateEncounter(at: coord, completion: done)
            }
        )
    }

    @MainActor
    private func presentYouWin() {
        overlayPresenter.present(
            fadeWorldOut: false,
            makeViewController: { YouWinViewController() },
            onResolved: { [weak self] done in
                self?.exitToLevelSelect()
                done()
            }
        )
    }

    @MainActor
    private func exitToLevelSelect() {
        guard !isExitingToLevelSelect else { return }
        isExitingToLevelSelect = true

        Task {
            if let snapshot = gameScene?.currentWorld {
                try? await session.saveService.save(snapshot)
            }
            await session.refreshContinueEligibility()

            let menu = MenuViewController(session: session)
            let levelSelect = LevelSelectViewController(session: session)
            let nav = LandscapeNavigationController(rootViewController: menu)
            nav.setNavigationBarHidden(true, animated: false)
            nav.pushViewController(levelSelect, animated: false)

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
