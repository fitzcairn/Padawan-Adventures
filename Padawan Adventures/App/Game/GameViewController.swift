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
            worldFx: session.selectedLevel.worldFx,
            spriteLibrary: session.spriteLibrary,
            playerSpriteConfig: session.playerConfig.sprite,
            itemsConfig: session.itemsConfig,
            treasureItemID: session.selectedLevel.treasure,
            floorTileSetLibrary: session.floorTileSetLibrary,
            gateSpriteSetLibrary: session.gateSpriteSetLibrary,
            saveService: session.saveService
        )
        scene.scaleMode = .aspectFill
        scene.onEnemyContact = { [weak self] enemyID in
            self?.presentEnemyFight(enemyID: enemyID)
        }
        scene.onEnemyNoticed = { [weak self] enemyID in
            self?.playEnemyNoticeFx(enemyID: enemyID)
        }
        scene.onPitEntered = { [weak self] approach in
            self?.playPlayerFx("pit")
            self?.presentPit(approach: approach)
        }
        scene.onGateEntered = { [weak self] gate, approach in
            self?.presentGate(at: gate, approach: approach)
        }
        scene.onPickupCollected = { [weak self] kind in
            self?.handlePickupCollected(kind)
        }
        scene.onTreasureCelebrationStarted = { [weak self] in
            self?.playPlayerFx("pickup_treasure")
            BackgroundMusicController.shared.applyScreen(named: "you_win")
        }
        scene.onTreasureCollected = { [weak self] in
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
            guard EnergyMechanic.isEnabled else { return }
            playPlayerFx("pickup_energy")
            hud?.addBolt()
        case .treasure:
            break
        }
    }

    private func playPlayerFx(_ event: String) {
        SoundEffectsController.shared.play(event: event, from: session.playerConfig.fx)
    }

    private func playEnemyNoticeFx(enemyID: UUID) {
        guard let typeID = gameScene?.currentWorld.entity(id: enemyID)?.enemyTypeID,
              let typeFx = session.enemyConfig.type(named: typeID)?.fx else { return }
        SoundEffectsController.shared.play(event: "notice", from: typeFx)
    }

    @MainActor
    private func presentEnemyFight(enemyID: UUID) {
        guard let scene = gameScene else { return }
        if EnergyMechanic.isEnabled {
            if DefeatRules.isDefeatedByEnemy(energy: scene.currentWorld.energyCount) {
                presentDefeat()
                return
            }
            scene.deductEnergy()
            hud?.removeBolt()
        }
        // World HUD is a UIKit overlay (not faded with SpriteKit). Hide it for the whole
        // combat session so it cannot flash between combat dismiss and defeat / world-in.
        setWorldHUDHidden(true)

        let typeID = scene.currentWorld.entity(id: enemyID)?.enemyTypeID
        let enemyType = typeID.flatMap { session.enemyConfig.type(named: $0) }
            ?? EnemyConfig.fallback.type(named: "spider")
            ?? EnemyTypeConfig(
                letter: "E",
                color: "#FF0000",
                tilesPerSecond: 1,
                forgetSeconds: 3
            )
        let enemySprite = typeID.flatMap { session.enemyConfig.spriteConfig(for: $0) }
        let combatSprite = session.playerConfig.combatSprite
        let healthCount = scene.currentWorld.healthCount
        let hudConfig = loadHudConfig()
        let playerFx = session.playerConfig.fx
        let letterSoundRepeatSeconds = session.selectedLetterSoundRepeatSeconds
        let letterSpawnRate = session.selectedCombatLetterSpawnRate
        let letterCase = session.selectedCombatLetterCase
        let slashMaxSeconds = session.enemyConfig.slashMaxSeconds
        let slashMaxScreenWidthFraction = session.enemyConfig.slashMaxScreenWidthFraction
        let outcomeBox = CombatOutcomeBox()

        let context = CombatPresentationContext(
            enemyType: enemyType,
            healthCount: healthCount,
            playerFx: playerFx,
            hudConfig: hudConfig,
            letterSoundRepeatSeconds: letterSoundRepeatSeconds,
            letterSpawnRate: letterSpawnRate,
            letterCase: letterCase,
            slashMaxSeconds: slashMaxSeconds,
            slashMaxScreenWidthFraction: slashMaxScreenWidthFraction,
            spriteLibrary: session.spriteLibrary,
            letterSpriteSetLibrary: session.letterSpriteSetLibrary,
            combatSprite: combatSprite,
            enemySprite: enemySprite,
            wallHeight: isoConfig.wallHeight,
            isoSquash: isoConfig.tileHeight / max(isoConfig.tileWidth, 1)
        )
        // Each encounter rolls its own arena from the level's weighted list.
        var minigameRNG = SystemRandomNumberGenerator()
        let chosenMinigame = session.selectedCombatConfig.pickMinigame(using: &minigameRNG)
        GameLogger.mark(
            .combat,
            """
            presenting \(chosenMinigame.kind.rawValue) vs '\(enemyType.sprite ?? "none")' \
            (hearts: \(healthCount), \
            weights: \(session.selectedCombatConfig.minigames.map { "\($0.kind.rawValue)=\($0.weight)" }.joined(separator: " ")))
            """
        )

        // Notice stingers can still be playing when contact starts combat — duck them out.
        SoundEffectsController.shared.fadeOutAndStop(
            trackID: enemyType.fx.trackID(for: "notice")
        )

        BackgroundMusicController.shared.apply(session.selectedGameMusic.combatCue)
        MemoryProbe.mark("minigame-present-combat")

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                self.makeOverlayHost { finish in
                    CombatMinigameFactory.makeView(
                        config: chosenMinigame,
                        context: context,
                        onFinished: { outcome in
                            outcomeBox.outcome = outcome
                            finish()
                        }
                    )
                }
            },
            onResolved: { [weak self] done in
                MemoryProbe.mark("minigame-dismiss-combat")
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                switch outcomeBox.outcome {
                case let .won(starsAwarded):
                    BackgroundMusicController.shared.apply(
                        MusicCue.parse(self.session.selectedLevelMusic)
                    )
                    scene.resolveEnemyEncounter(enemyID: enemyID) {
                        // Reveal the level HUD before the coin count-up so sparkles are visible.
                        self.setWorldHUDHidden(false)
                        Task {
                            await self.session.recordStat { $0.enemiesKilled += 1 }
                            await self.awardLevelStars(count: starsAwarded)
                        }
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

    /// Builds a fullscreen host with world.yaml overlay dismiss timing applied.
    private func makeOverlayHost<Content: View>(
        @ViewBuilder content: @escaping (_ finish: @escaping () -> Void) -> Content
    ) -> FullscreenOverlayHost {
        let dismissSeconds = session.appConfig.display.overlayDismissSeconds
        return FullscreenOverlayHost { finish in
            content(finish)
                .environment(\.overlayDismissSeconds, dismissSeconds)
        }
    }

    @MainActor
    private func presentPit(approach: GridCoord) {
        guard let scene = gameScene else { return }
        if DefeatRules.isDefeatedByPit(health: scene.currentWorld.healthCount) {
            presentDefeat()
            return
        }

        let pitConfig = session.selectedPitConfig
        // Each pit rolls its own game from the level's weighted list.
        var minigameRNG = SystemRandomNumberGenerator()
        let chosenMinigame = pitConfig.pickMinigame(using: &minigameRNG)
        let playerFx = session.playerConfig.fx
        let hudConfig = loadHudConfig()
        let outcomeBox = PitOutcomeBox()

        BackgroundMusicController.shared.apply(session.selectedGameMusic.pitCue)
        MemoryProbe.mark("minigame-present-pit")

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                self.makeOverlayHost { finish in
                    PitMinigameFactory.makeView(
                        config: chosenMinigame,
                        pitFx: pitConfig.fx,
                        playerFx: playerFx,
                        hudConfig: hudConfig,
                        pitSpriteSetLibrary: self.session.pitSpriteSetLibrary,
                        floorTileSetLibrary: self.session.floorTileSetLibrary,
                        isoConfig: self.isoConfig,
                        spriteLibrary: self.session.spriteLibrary,
                        playerSpriteConfig: self.session.playerConfig.sprite,
                        onFinished: { outcome in
                            outcomeBox.outcome = outcome
                            finish()
                        }
                    )
                }
            },
            onResolved: { [weak self] done in
                MemoryProbe.mark("minigame-dismiss-pit")
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                BackgroundMusicController.shared.apply(
                    MusicCue.parse(self.session.selectedLevelMusic)
                )
                switch outcomeBox.outcome {
                case let .won(starsAwarded):
                    Task {
                        await self.session.recordStat { $0.pitsCrossed += 1 }
                        await self.awardLevelStars(count: starsAwarded)
                    }
                    scene.resolvePitWin(completion: done)
                case .lost, .none:
                    scene.deductHealth()
                    self.hud?.removeHeart()
                    if DefeatRules.isDefeatedByPit(health: scene.currentWorld.healthCount) {
                        done()
                        self.presentDefeat()
                    } else {
                        scene.resolvePitTimeout(approach: approach, completion: done)
                    }
                }
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
                self.makeOverlayHost { finish in
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
    private func presentGate(at coord: GridCoord, approach: GridCoord) {
        let gateConfig = session.selectedGateConfig

        // Probabilistic free-open: skip the puzzle and open the gate with SFX.
        guard Double.random(in: 0..<1) < gateConfig.minigameChance else {
            guard let scene = gameScene else { return }
            Task {
                await self.session.recordStat { $0.gatesOpened += 1 }
            }
            scene.resolveGateEncounter(at: coord)
            return
        }

        let kind = gameScene?.currentWorld.tile(at: coord)?.gateMinigame ?? .spelling
        let chosen = gateConfig.minigame(for: kind) ?? gateConfig.minigames[0]
        let playerFx = session.playerConfig.fx
        let hudConfig = loadHudConfig()
        let outcomeBox = GateOutcomeBox()

        let musicName = chosen.music ?? session.selectedGameMusic.gate
        BackgroundMusicController.shared.apply(MusicCue.parse(musicName))
        MemoryProbe.mark("minigame-present-gate")

        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                self.makeOverlayHost { finish in
                    GateMinigameFactory.makeView(
                        config: chosen,
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
                MemoryProbe.mark("minigame-dismiss-gate")
                guard let self, let scene = self.gameScene else {
                    done()
                    return
                }
                BackgroundMusicController.shared.apply(
                    MusicCue.parse(self.session.selectedLevelMusic)
                )
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
        guard count > 0, let resourceName = session.selectedLevelResourceName else { return }
        let previous = session.playerState?.levels[resourceName]?.starsCurrent ?? 0
        await session.addLevelStars(resourceName: resourceName, count: count)
        let stars = session.playerState?.levels[resourceName]?.starsCurrent ?? previous
        if let hud {
            await hud.animateStarAward(from: previous, to: stars)
        }
    }

    @MainActor
    private func presentYouWin() {
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
                    self.makeOverlayHost { finish in
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
            session.releaseLevelScopedSprites()
            session.startObservingMemoryPressure()

            let flow = LandscapeSwiftUIHost(
                rootView: FlowRootView(
                    session: session,
                    router: .postGameRouter()
                )
            )

            AppWindow.setRoot(flow, in: view.window ?? AppWindow.key)
        }
    }
}

/// Captures combat result across the overlay finish callback.
private final class CombatOutcomeBox {
    var outcome: CombatOutcome?
}

/// Captures pit puzzle result across the overlay finish callback.
private final class PitOutcomeBox {
    var outcome: PitOutcome?
}

/// Captures gate puzzle result across the overlay finish callback.
private final class GateOutcomeBox {
    var outcome: GateOutcome?
}
