//
//  GameViewController.swift
//  Padawan Adventures
//

import UIKit
import SpriteKit
import SwiftUI

final class GameViewController: LandscapeHostingController {
    private let world: GameWorld
    private let isoConfig: IsometricConfig
    private let session: AppSession
    private weak var gameScene: GameScene?
    private weak var hud: GameHUDView?
    private var isExitingToLevelSelect = false
    private var didApplyLevelMusic = false
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
            playerFx: session.playerConfig.fx,
            worldFx: session.seedConfig.fx,
            saveService: session.saveService
        )
        scene.scaleMode = .aspectFill
        scene.onEnemyContact = { [weak self] enemyID in
            self?.playEnemyContactFx(enemyID: enemyID)
            self?.presentEnemyFight(enemyID: enemyID)
        }
        scene.onPitEntered = { [weak self] in
            self?.playPlayerFx("pit")
            self?.presentPit()
        }
        scene.onBoomEntered = { [weak self] coord in
            self?.playPlayerFx("boom")
            self?.presentDestructibleWall(at: coord)
        }
        scene.onGateEntered = { [weak self] gate, approach in
            self?.playPlayerFx("gate")
            self?.presentGate(at: gate, approach: approach)
        }
        scene.onPickupCollected = { [weak self] kind in
            self?.handlePickupCollected(kind)
        }
        scene.onTreasureCollected = { [weak self] in
            self?.playPlayerFx("pickup_treasure")
            self?.presentYouWin()
        }
        scene.onWorldSaved = { [weak self] snapshot in
            Task { @MainActor in
                await self?.session.syncVitals(from: snapshot)
            }
        }
        scene.onVitalsRestored = { [weak self] health, energy in
            self?.hud?.setVitals(health: health, energy: energy)
        }
        skView.presentScene(scene)
        gameScene = scene

        skView.ignoresSiblingOrder = true
        skView.showsFPS = true
        skView.showsNodeCount = true

        installHUD()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // One-shot: modal overlays also re-trigger viewDidAppear; don't clobber win/minigame cues.
        guard !didApplyLevelMusic else { return }
        didApplyLevelMusic = true
        BackgroundMusicController.shared.apply(MusicCue.parse(session.selectedLevelMusic))
    }

    private func installHUD() {
        let hudConfig = loadHudConfig()

        let levelResource = session.selectedLevelResourceName
        let starsCount = levelResource.flatMap { session.playerState?.levels[$0]?.starsCurrent } ?? 0
        let hud = GameHUDView(
            config: hudConfig,
            levelName: session.selectedLevelName,
            healthCount: world.healthCount,
            energyCount: world.energyCount,
            starsCount: starsCount
        )
        hud.onFleeTapped = { [weak self] in
            self?.exitToLevelSelect(completedLevel: false)
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
            playPlayerFx("pickup_health")
            hud?.addHeart()
        case .energy:
            playPlayerFx("pickup_energy")
            hud?.addBolt()
        case .treasure:
            break
        }
    }

    private func playPlayerFx(_ event: String) {
        SoundEffectsController.shared.play(event: event, from: session.playerConfig.fx)
    }

    private func playEnemyContactFx(enemyID: UUID) {
        let typeID = gameScene?.currentWorld.entity(id: enemyID)?.enemyTypeID
        if let typeID,
           let typeFx = session.enemyConfig.type(named: typeID)?.fx,
           typeFx.trackID(for: "contact") != nil {
            SoundEffectsController.shared.play(event: "contact", from: typeFx)
            return
        }
        playPlayerFx("enemy_contact")
    }

    @MainActor
    private func presentEnemyFight(enemyID: UUID) {
        guard let scene = gameScene else { return }
        if DefeatRules.isDefeatedByEnemy(energy: scene.currentWorld.energyCount) {
            presentDefeat()
            return
        }
        scene.deductEnergy()
        hud?.removeBolt()
        // World HUD is a UIKit overlay (not faded with SpriteKit). Hide it for the whole
        // combat session so it cannot flash between combat dismiss and defeat / world-in.
        setWorldHUDHidden(true)

        let typeID = scene.currentWorld.entity(id: enemyID)?.enemyTypeID
        let enemyType = typeID.flatMap { session.enemyConfig.type(named: $0) }
            ?? EnemyConfig.fallback.type(named: "grunt")
            ?? EnemyTypeConfig(
                letter: "E",
                color: "#FF0000",
                tilesPerSecond: 1,
                forgetSeconds: 3
            )
        let healthCount = scene.currentWorld.healthCount
        let hudConfig = loadHudConfig()
        let playerFx = session.playerConfig.fx
        let outcomeBox = CombatOutcomeBox()

        BackgroundMusicController.shared.applyScreen(named: "combat")

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                FullscreenOverlayHost { finish in
                    EnemyMinigameView(
                        enemyType: enemyType,
                        healthCount: healthCount,
                        playerFx: playerFx,
                        hudConfig: hudConfig,
                        onFinished: { outcome in
                            outcomeBox.outcome = outcome
                            finish()
                        }
                    )
                }
            },
            onResolved: { [weak self] done in
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                switch outcomeBox.outcome {
                case let .won(starsAwarded):
                    Task {
                        await self.session.recordStat { $0.enemiesKilled += 1 }
                        await self.awardLevelStars(count: starsAwarded)
                    }
                    BackgroundMusicController.shared.apply(
                        MusicCue.parse(self.session.selectedLevelMusic)
                    )
                    scene.resolveEnemyEncounter(enemyID: enemyID) {
                        self.setWorldHUDHidden(false)
                        done()
                    }
                case .lost, .none:
                    // Keep world HUD hidden; presentDefeat silences then restores level music.
                    done()
                    self.presentDefeat()
                }
            }
        )
    }

    private func setWorldHUDHidden(_ hidden: Bool) {
        hud?.isHidden = hidden
    }

    private func loadHudConfig() -> HudConfig {
        do {
            let loaded = try HudConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        } catch {
            return .fallback
        }
    }

    @MainActor
    private func presentPit() {
        guard let scene = gameScene else { return }
        if DefeatRules.isDefeatedByPit(health: scene.currentWorld.healthCount) {
            presentDefeat()
            return
        }
        scene.deductHealth()
        hud?.removeHeart()

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                FullscreenOverlayHost { finish in
                    PitMinigameView(onFinished: finish)
                }
            },
            onResolved: { [weak self] done in
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                Task {
                    await self.session.recordStat { $0.pitsCrossed += 1 }
                    await self.awardLevelStar()
                }
                scene.resolvePitEncounter(completion: done)
            }
        )
    }

    @MainActor
    private func presentDefeat() {
        BackgroundMusicController.shared.applyScreen(named: "defeat")
        setWorldHUDHidden(true)
        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                FullscreenOverlayHost { finish in
                    DefeatView(onFinished: finish)
                }
            },
            onResolved: { [weak self] done in
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                scene.restoreFromContinuePoint {
                    BackgroundMusicController.shared.apply(
                        MusicCue.parse(self.session.selectedLevelMusic)
                    )
                    self.setWorldHUDHidden(false)
                    done()
                }
            }
        )
    }

    @MainActor
    private func presentDestructibleWall(at coord: GridCoord) {
        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                FullscreenOverlayHost { finish in
                    DestructibleWallMinigameView(onFinished: finish)
                }
            },
            onResolved: { [weak self] done in
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                Task {
                    await self.session.recordStat { $0.wallsBlownUp += 1 }
                    await self.awardLevelStar()
                }
                scene.resolveBoomEncounter(at: coord, completion: done)
            }
        )
    }

    @MainActor
    private func presentGate(at coord: GridCoord, approach: GridCoord) {
        let puzzleConfig = session.selectedGateConfig
        let playerFx = session.playerConfig.fx
        let hudConfig = loadHudConfig()
        let outcomeBox = GateOutcomeBox()

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                FullscreenOverlayHost { finish in
                    GateMinigameView(
                        puzzleConfig: puzzleConfig,
                        playerFx: playerFx,
                        hudConfig: hudConfig,
                        onFinished: { outcome in
                            outcomeBox.outcome = outcome
                            finish()
                        }
                    )
                }
            },
            onResolved: { [weak self] done in
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                switch outcomeBox.outcome {
                case let .won(starsAwarded):
                    Task {
                        await self.session.recordStat { $0.gatesOpened += 1 }
                        await self.awardLevelStars(count: starsAwarded)
                    }
                    scene.resolveGateEncounter(at: coord, completion: done)
                case .lost, .none:
                    scene.resolveGateTimeout(approach: approach, completion: done)
                }
            }
        )
    }

    @MainActor
    private func awardLevelStar() async {
        await awardLevelStars(count: 1)
    }

    @MainActor
    private func awardLevelStars(count: Int) async {
        guard let resourceName = session.selectedLevelResourceName else { return }
        await session.addLevelStars(resourceName: resourceName, count: count)
        let stars = session.playerState?.levels[resourceName]?.starsCurrent ?? 0
        hud?.setStars(stars)
    }

    @MainActor
    private func presentYouWin() {
        BackgroundMusicController.shared.applyScreen(named: "you_win")
        Task { @MainActor in
            var didBeatPrevious = false
            var newScore = 0
            if let resourceName = session.selectedLevelResourceName,
               let result = await session.finalizeLevelStars(resourceName: resourceName) {
                didBeatPrevious = result.didBeatPrevious
                newScore = result.newScore
            }

            overlayPresenter.present(
                fadeWorldOut: false,
                makeViewController: {
                    FullscreenOverlayHost { finish in
                        YouWinView(
                            didBeatPreviousScore: didBeatPrevious,
                            newScore: newScore,
                            onFinished: finish
                        )
                    }
                },
                onResolved: { [weak self] done in
                    self?.exitToLevelSelect(completedLevel: true)
                    done()
                }
            )
        }
    }

    @MainActor
    private func exitToLevelSelect(completedLevel: Bool) {
        guard !isExitingToLevelSelect else { return }
        isExitingToLevelSelect = true

        Task {
            if let snapshot = gameScene?.currentWorld {
                await session.syncVitals(from: snapshot)
                if completedLevel {
                    if let resourceName = session.selectedLevelResourceName {
                        await session.markLevelCompleted(resourceName: resourceName)
                    }
                    try? await session.saveService.delete()
                } else {
                    try? await session.saveService.save(snapshot)
                }
            }
            await session.refreshContinueEligibility()

            let flow = LandscapeSwiftUIHost(
                rootView: FlowRootView(
                    session: session,
                    router: .postGameRouter()
                )
            )

            let window = view.window ?? AppWindow.key
            window?.rootViewController = flow
            window?.makeKeyAndVisible()
        }
    }
}

/// Captures combat result across the overlay finish callback.
private final class CombatOutcomeBox {
    var outcome: CombatOutcome?
}

/// Captures gate puzzle result across the overlay finish callback.
private final class GateOutcomeBox {
    var outcome: GateOutcome?
}
