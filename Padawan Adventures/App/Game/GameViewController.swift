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
    private let runExitHandler = GameRunExitHandler()
    private var didApplyLevelMusic = false
    private var worldTutorial: WorldTutorialController?
    private var jetpackNeedGateHost: UIViewController?
    private lazy var cachedHudConfig: HudConfig = Self.loadHudConfig()
    private lazy var overlayPresenter = FullscreenOverlayPresenter(
        host: self,
        fadeWorldOut: { [weak self] duration, completion in
            self?.fadeLevelChrome(visible: false, duration: duration, completion: completion)
        },
        fadeWorldIn: { [weak self] duration, completion in
            self?.fadeLevelChrome(visible: true, duration: duration, completion: completion)
        }
    )
    private lazy var encounterCoordinator = GameEncounterCoordinator(
        overlayPresenter: overlayPresenter,
        buildOverlayHost: { [weak self] content in
            guard let self else {
                return FullscreenOverlayHost { _ in AnyView(EmptyView()) }
            }
            return self.makeOverlayHost { finish in
                content(finish)
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
            npcsConfig: session.npcsConfig,
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
            self?.presentPit(approach: approach)
        }
        scene.onGateEntered = { [weak self] gate, approach in
            self?.presentGate(at: gate, approach: approach)
        }
        scene.onMerchantVisible = { [weak self] merchantID in
            self?.playMerchantFx(merchantID: merchantID, event: "visible")
        }
        scene.onMerchantContact = { [weak self] merchantID, approach in
            self?.presentMerchant(merchantID: merchantID, approach: approach)
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
        #if DEBUG
        skView.showsFPS = true
        skView.showsNodeCount = true
        #endif

        installHUD()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // One-shot: modal overlays also re-trigger viewDidAppear; don't clobber win/minigame cues.
        guard !didApplyLevelMusic else { return }
        didApplyLevelMusic = true
        BackgroundMusicController.shared.apply(MusicCue.parse(session.selectedLevelMusic))
        startWorldTutorialIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        worldTutorial?.cancel()
        worldTutorial = nil
    }

    private func startWorldTutorialIfNeeded() {
        guard session.selectedLevel.worldTutorial,
              !session.hasSeenWorldTutorial,
              let scene = gameScene,
              scene.currentWorld.playerPosition == scene.currentWorld.spawn else { return }

        let controller = WorldTutorialController(scene: scene) { [weak self] in
            Task { await self?.session.markWorldTutorialSeen() }
        }
        worldTutorial = controller
        controller.start()
    }

    private func installHUD() {
        let hudConfig = cachedHudConfig

        let levelResource = session.selectedLevelResourceName
        let starsCount = levelResource.flatMap { session.playerState?.levels[$0]?.starsCurrent } ?? 0
        let hud = GameHUDView(
            config: hudConfig,
            healthCount: world.healthCount,
            energyCount: world.energyCount,
            starsCount: starsCount,
            inventorySlots: session.playerState?.itemSlots ?? PlayerGameState.emptyItemSlots,
            merchantCatalog: session.itemsConfig.merchant
        )
        hud.onInventorySlotTapped = { [weak self] index, itemID in
            self?.handleInventorySlotTapped(index: index, itemID: itemID) ?? false
        }
        hud.onFleeTapped = { [weak self] in
            guard let self else { return }
            self.runExitHandler.exitToLevelSelect(
                completedLevel: false,
                gameScene: self.gameScene,
                session: self.session,
                hostWindow: self.view.window
            )
        }
        view.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.topAnchor.constraint(equalTo: view.topAnchor),
            hud.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hud.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hud.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hud.embedInventory(in: self)
        self.hud = hud
    }

    private func handleInventorySlotTapped(index: Int, itemID: String) -> Bool {
        guard let scene = gameScene,
              !scene.isPausedForEncounter,
              !scene.isResolvingPickup,
              !overlayPresenter.isBusy,
              jetpackNeedGateHost == nil
        else { return false }

        if itemID == JetpackGateUse.itemID {
            return useJetpackFromInventory(index: index)
        }
        if itemID == SatelliteScanUse.itemID {
            return useSatelliteFromInventory(index: index)
        }
        if itemID == ScannerUse.itemID {
            return useScannerFromInventory(index: index)
        }

        if let sound = session.itemsConfig.merchantItem(itemID)?.sound, !sound.isEmpty {
            SoundEffectsController.shared.play(trackID: sound)
        }
        persistClearedInventorySlot(index: index)
        return true
    }

    private func useJetpackFromInventory(index: Int) -> Bool {
        guard let scene = gameScene else { return false }
        guard let result = JetpackGateUse.resolve(in: scene.currentWorld) else {
            presentJetpackNeedGateModal()
            return false
        }
        persistClearedInventorySlot(index: index)
        Task { await session.recordStat { $0.gatesOpened += 1 } }
        scene.useJetpack(over: result.gateCoord, landing: result.landing)
        return true
    }

    private func useSatelliteFromInventory(index: Int) -> Bool {
        guard let scene = gameScene,
              let origin = SatelliteScanUse.artifactCoord(in: scene.currentWorld)
        else { return false }
        Task { await session.setItemSlot(index: index, itemID: nil) }
        scene.performSatelliteScan(at: origin) { [weak self] in
            guard let self else { return }
            self.hud?.playUseEffects(index: index, itemID: SatelliteScanUse.itemID)
            self.persistClearedInventorySlot(index: index)
        }
        return false
    }

    private func useScannerFromInventory(index: Int) -> Bool {
        guard let scene = gameScene else { return false }
        let origin = ScannerUse.origin(in: scene.currentWorld)
        Task { await session.setItemSlot(index: index, itemID: nil) }
        scene.performScannerScan(at: origin) { [weak self] in
            guard let self else { return }
            self.hud?.playUseEffects(index: index, itemID: ScannerUse.itemID)
            self.persistClearedInventorySlot(index: index)
        }
        return false
    }

    private func persistClearedInventorySlot(index: Int) {
        Task {
            await session.setItemSlot(index: index, itemID: nil)
            await MainActor.run {
                hud?.setInventorySlots(
                    session.playerState?.itemSlots ?? PlayerGameState.emptyItemSlots,
                    catalog: session.itemsConfig.merchant
                )
            }
        }
    }

    private func presentJetpackNeedGateModal() {
        guard jetpackNeedGateHost == nil else { return }
        gameScene?.isPausedForEncounter = true
        let host = UIHostingController(rootView: JetpackNeedGateModal { [weak self] in
            self?.dismissJetpackNeedGateModal()
        })
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        jetpackNeedGateHost = host
    }

    private func dismissJetpackNeedGateModal() {
        guard let host = jetpackNeedGateHost else { return }
        jetpackNeedGateHost = nil
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        if !overlayPresenter.isBusy {
            gameScene?.isPausedForEncounter = false
        }
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

    private func playMerchantFx(merchantID: UUID, event: String) {
        let npcID = gameScene?.currentWorld.entity(id: merchantID)?.npcID ?? MerchantSpawner.npcID
        SoundEffectsController.shared.play(event: event, from: session.npcsConfig.fx(for: npcID))
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
        let enemyEntity = scene.currentWorld.entity(id: enemyID)
        let typeID = enemyEntity?.enemyTypeID
        let baseEnemyType = typeID.flatMap { session.enemyConfig.type(named: $0) }
            ?? EnemyConfig.fallback.type(named: "spider")
            ?? EnemyTypeConfig(
                letter: "E",
                color: "#FF0000",
                tilesPerSecond: 1,
                forgetSeconds: 3
            )
        // Slash shots use the level's single-character letter pool, not enemies.yaml.
        let enemyType = baseEnemyType.withShotTypes(from: session.selectedLevel.vocabulary)
        let enemySprite = typeID.flatMap { session.enemyConfig.spriteConfig(for: $0) }
        let projectileSprite = typeID.flatMap { session.enemyConfig.projectileSpriteConfig(for: $0) }
        let combatSprite = session.playerConfig.combatSprite
        let healthCount = scene.currentWorld.healthCount
        let hudConfig = cachedHudConfig
        let playerFx = session.playerConfig.fx
        let slashMaxSeconds = session.enemyConfig.slashMaxSeconds
        let slashMaxScreenWidthFraction = session.enemyConfig.slashMaxScreenWidthFraction

        // Generation pins a combat kind onto each enemy; otherwise roll from weights (legacy saves).
        var minigameRNG = SystemRandomNumberGenerator()
        let chosenMinigame = enemyEntity?.combatMinigame
            .flatMap { session.selectedCombatConfig.minigame(for: $0) }
            ?? (try? session.selectedCombatConfig.pickMinigame(using: &minigameRNG))
            ?? CombatConfig.fallback.minigames[0]

        let slash: CombatSlashConfig?
        if case .slash(let config) = chosenMinigame {
            slash = config
        } else {
            slash = nil
        }
        let graphemeSoundRepeatSeconds = slash?.graphemeSoundRepeatSeconds
            ?? CombatMinigameEngine.Config.defaultGraphemeSoundRepeatSeconds
        let minDecoyCount = slash?.minDecoyCount
            ?? CombatMinigameEngine.Config.defaultMinDecoyCount
        let maxDecoyCount = slash?.maxDecoyCount
            ?? CombatMinigameEngine.Config.defaultMaxDecoyCount
        let graphemeCase = slash?.graphemeCase ?? .upper
        let vocabulary = slash?.vocabulary ?? session.selectedLevel.vocabulary

        let context = CombatPresentationContext(
            enemyType: enemyType,
            healthCount: healthCount,
            playerFx: playerFx,
            hudConfig: hudConfig,
            graphemeSoundRepeatSeconds: graphemeSoundRepeatSeconds,
            minDecoyCount: minDecoyCount,
            maxDecoyCount: maxDecoyCount,
            graphemeCase: graphemeCase,
            vocabulary: vocabulary,
            vocabularySampler: session.vocabularySampler,
            slashMaxSeconds: slashMaxSeconds,
            slashMaxScreenWidthFraction: slashMaxScreenWidthFraction,
            spriteLibrary: session.spriteLibrary,
            letterSpriteSetLibrary: session.letterSpriteSetLibrary,
            combatSprite: combatSprite,
            enemySprite: enemySprite,
            projectileSprite: projectileSprite,
            wallHeight: isoConfig.wallHeight,
            isoSquash: isoConfig.tileHeight / max(isoConfig.tileWidth, 1)
        )
        GameLogger.mark(
            .combat,
            """
            presenting \(chosenMinigame.kind.rawValue) vs '\(enemyType.sprite ?? "none")' \
            (hearts: \(healthCount), \
            weights: \(session.selectedCombatConfig.minigames.map { "\($0.kind.rawValue)=\($0.weight)" }.joined(separator: " ")))
            """
        )

        let tutorialKey = chosenMinigame.kind.rawValue
        let leadInSeconds = MinigameTutorialView<EmptyView>.leadInSeconds(
            forKindRawValue: tutorialKey
        )
        encounterCoordinator.presentMinigame(
            music: MusicCue.parse(session.selectedCombatConfig.music),
            memoryLabel: "combat",
            needsTutorial: { [weak self] in
                !(self?.session.hasSeenMinigameTutorial(tutorialKey) ?? true)
            },
            tutorialKey: tutorialKey,
            onTutorialAcknowledged: { [weak self] in
                self?.session.markMinigameTutorialSeen(tutorialKey)
            },
            makeDemoView: {
                CombatMinigameFactory.makeDemoView(
                    config: chosenMinigame,
                    context: context,
                    leadInSeconds: leadInSeconds
                )
            },
            makeView: { finish in
                CombatMinigameFactory.makeView(
                    config: chosenMinigame,
                    context: context,
                    onFinished: finish
                )
            },
            onOutcome: { [weak self] outcome, returnToWorld in
                guard let self, let scene = self.gameScene else {
                    returnToWorld.dismissWhileCovered { $0() }
                    return
                }
                switch outcome {
                case let .won(starsAwarded):
                    BackgroundMusicController.shared.apply(
                        MusicCue.parse(self.session.selectedLevelMusic)
                    )
                    let defeatNode = scene.prepareEnemyEncounterWin(enemyID: enemyID)
                    returnToWorld.crossfadeToWorld { done in
                        // HUD is already fading in with the world via `fadeLevelChrome`.
                        scene.revealEnemyEncounterWin(defeatNode: defeatNode) {
                            Task {
                                await self.session.recordStat { $0.enemiesKilled += 1 }
                                await self.awardLevelStars(count: starsAwarded)
                            }
                            done()
                        }
                    }
                case .lost, .abandoned, .none:
                    // HUD stays faded with the world; presentDefeat restores both together.
                    // Combat does not offer leave; `.abandoned` is included for exhaustiveness.
                    returnToWorld.dismissWhileCovered { done in
                        done()
                        self.presentDefeat()
                    }
                }
            }
        )
    }

    @MainActor
    private func presentMerchant(merchantID: UUID, approach: GridCoord) {
        let resourceName = session.selectedLevelResourceName ?? ""
        let tileSeed = gameScene?.currentWorld.tileSeed ?? 0
        encounterCoordinator.presentMinigame(
            music: MusicCue.parse("merchant"),
            memoryLabel: "merchant",
            needsTutorial: { false },
            tutorialKey: "merchant",
            onTutorialAcknowledged: {},
            makeDemoView: { EmptyView() },
            makeView: { finish in
                MerchantMinigameView(
                    appSession: self.session,
                    resourceName: resourceName,
                    tileSeed: tileSeed,
                    onFinished: finish
                )
            },
            onOutcome: { [weak self] _, returnToWorld in
                guard let self, let scene = self.gameScene else {
                    returnToWorld.dismissWhileCovered { $0() }
                    return
                }
                BackgroundMusicController.shared.apply(
                    MusicCue.parse(self.session.selectedLevelMusic)
                )
                self.refreshWorldHUDAfterMerchant()
                let departNode = scene.prepareMerchantDepart(
                    merchantID: merchantID,
                    approach: approach
                )
                returnToWorld.crossfadeToWorld { done in
                    scene.revealMerchantDepart(departNode: departNode, completion: done)
                }
            }
        )
    }

    private func refreshWorldHUDAfterMerchant() {
        let resourceName = session.selectedLevelResourceName
        let stars = resourceName.flatMap { session.playerState?.levels[$0]?.starsCurrent } ?? 0
        hud?.setStars(stars)
        hud?.setInventorySlots(
            session.playerState?.itemSlots ?? PlayerGameState.emptyItemSlots,
            catalog: session.itemsConfig.merchant
        )
    }

    /// Fades the SpriteKit world and UIKit HUD together so level chrome returns in lockstep.
    private func fadeLevelChrome(
        visible: Bool,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        var remaining = 2
        let arrive = {
            remaining -= 1
            guard remaining == 0 else { return }
            completion()
        }

        if let scene = gameScene {
            if visible {
                scene.fadeSimulationIn(duration: duration, completion: arrive)
            } else {
                scene.fadeSimulationOut(duration: duration, completion: arrive)
            }
        } else {
            arrive()
        }

        fadeWorldHUD(visible: visible, duration: duration, completion: arrive)
    }

    private func fadeWorldHUD(
        visible: Bool,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        guard let hud else {
            completion()
            return
        }

        if visible {
            hud.isHidden = false
            hud.alpha = 0
            hud.isUserInteractionEnabled = true
        }

        guard duration > 0, UIView.areAnimationsEnabled else {
            hud.alpha = visible ? 1 : 0
            hud.isHidden = !visible
            hud.isUserInteractionEnabled = visible
            completion()
            return
        }

        UIView.animate(withDuration: duration, animations: {
            hud.alpha = visible ? 1 : 0
        }, completion: { _ in
            if !visible {
                hud.isHidden = true
            }
            hud.isUserInteractionEnabled = visible
            completion()
        })
    }

    private static func loadHudConfig() -> HudConfig {
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
            playPlayerFx("pit")
            presentDefeat()
            return
        }

        let pitConfig = session.selectedPitConfig
        // Generation pins a pit kind onto each pit tile; otherwise roll from weights (legacy saves).
        let pinnedKind = scene.currentWorld.playerPosition
            .flatMap { scene.currentWorld.tile(at: $0)?.pitMinigame }
        var minigameRNG = SystemRandomNumberGenerator()
        let chosenMinigame = pinnedKind.flatMap { pitConfig.minigame(for: $0) }
            ?? (try? pitConfig.pickMinigame(using: &minigameRNG))
            ?? PitConfig.fallback.minigames[0]
        let playerFx = session.playerConfig.fx
        let hudConfig = cachedHudConfig

        let tutorialKey = chosenMinigame.kind.rawValue
        let leadInSeconds = MinigameTutorialView<EmptyView>.leadInSeconds(
            forKindRawValue: tutorialKey
        )
        encounterCoordinator.presentMinigame(
            music: MusicCue.parse(session.selectedPitConfig.music),
            memoryLabel: "pit",
            needsTutorial: { [weak self] in
                !(self?.session.hasSeenMinigameTutorial(tutorialKey) ?? true)
            },
            tutorialKey: tutorialKey,
            onTutorialAcknowledged: { [weak self] in
                self?.session.markMinigameTutorialSeen(tutorialKey)
            },
            makeDemoView: {
                PitMinigameFactory.makeDemoView(
                    config: chosenMinigame,
                    pitFx: pitConfig.fx,
                    playerFx: playerFx,
                    hudConfig: hudConfig,
                    floorTileSetLibrary: self.session.floorTileSetLibrary,
                    isoConfig: self.isoConfig,
                    spriteLibrary: self.session.spriteLibrary,
                    playerSpriteConfig: self.session.playerConfig.sprite,
                    leadInSeconds: leadInSeconds
                )
            },
            makeView: { finish in
                PitMinigameFactory.makeView(
                    config: chosenMinigame,
                    pitFx: pitConfig.fx,
                    playerFx: playerFx,
                    hudConfig: hudConfig,
                    floorTileSetLibrary: self.session.floorTileSetLibrary,
                    isoConfig: self.isoConfig,
                    spriteLibrary: self.session.spriteLibrary,
                    playerSpriteConfig: self.session.playerConfig.sprite,
                    vocabularySampler: self.session.vocabularySampler,
                    onFinished: finish
                )
            },
            onOutcome: { [weak self] outcome, returnToWorld in
                guard let self, let scene = self.gameScene else {
                    returnToWorld.dismissWhileCovered { $0() }
                    return
                }
                BackgroundMusicController.shared.apply(
                    MusicCue.parse(self.session.selectedLevelMusic)
                )
                switch outcome {
                case let .won(starsAwarded):
                    Task {
                        await self.session.recordStat { $0.pitsCrossed += 1 }
                        await self.awardLevelStars(count: starsAwarded)
                    }
                    scene.preparePitWin()
                    returnToWorld.crossfadeToWorld { done in
                        scene.revealPitWin(completion: done)
                    }
                case .abandoned:
                    scene.preparePitTimeout(approach: approach)
                    returnToWorld.crossfadeToWorld { done in
                        scene.revealPitTimeout(completion: done)
                    }
                case .lost, .none:
                    scene.deductHealth()
                    self.hud?.removeHeart()
                    if DefeatRules.isDefeatedByPit(health: scene.currentWorld.healthCount) {
                        returnToWorld.dismissWhileCovered { done in
                            done()
                            self.presentDefeat()
                        }
                    } else {
                        scene.preparePitTimeout(approach: approach)
                        returnToWorld.crossfadeToWorld { done in
                            scene.revealPitTimeout(completion: done)
                        }
                    }
                }
            }
        )
        // After world FX have begun fading so the pit sting is not cleared with them.
        playPlayerFx("pit")
    }

    @MainActor
    private func presentDefeat() {
        BackgroundMusicController.shared.applyScreen(named: "defeat")
        overlayPresenter.present(
            fadeWorldOut: true,
            makeViewController: {
                self.makeOverlayHost { finish in
                    DefeatView(onFinished: finish)
                }
            },
            onResolved: { [weak self] returnToWorld in
                guard let self, let scene = self.gameScene else {
                    returnToWorld.dismissWhileCovered { $0() }
                    return
                }
                scene.prepareRestoreFromContinuePoint()
                returnToWorld.crossfadeToWorld { done in
                    scene.revealRestoreFromContinuePoint {
                        BackgroundMusicController.shared.apply(
                            MusicCue.parse(self.session.selectedLevelMusic)
                        )
                        done()
                    }
                }
            }
        )
    }

    @MainActor
    private func presentGate(at coord: GridCoord, approach: GridCoord) {
        let gateConfig = session.selectedGateConfig

        // Probabilistic free-open: skip the puzzle and open the gate with SFX.
        // Demo mode always runs the puzzle so every gate kind is reachable.
        guard session.appConfig.demoMode || Double.random(in: 0..<1) < gateConfig.minigameChance else {
            guard let scene = gameScene else { return }
            Task {
                await self.session.recordStat { $0.gatesOpened += 1 }
            }
            // Same world+HUD fade timing as minigame returns (no overlay crossfade).
            fadeLevelChrome(visible: false, duration: WorldFade.duration) { [weak self] in
                guard let self else { return }
                let prepared = scene.prepareGateEncounter(at: coord)
                self.fadeLevelChrome(visible: true, duration: WorldFade.duration) {
                    scene.revealGateEncounter(
                        gateNode: prepared.gateNode,
                        openedCoords: prepared.openedCoords
                    )
                }
            }
            return
        }

        let kind = gameScene?.currentWorld.tile(at: coord)?.gateMinigame ?? .soundOutWord
        let chosen = gateConfig.minigame(for: kind) ?? gateConfig.minigames[0]
        let playerFx = session.playerConfig.fx
        let hudConfig = cachedHudConfig

        let musicName = chosen.music ?? session.selectedGateConfig.music
        let tutorialKey = chosen.kind.rawValue
        let leadInSeconds = MinigameTutorialView<EmptyView>.leadInSeconds(
            forKindRawValue: tutorialKey
        )
        encounterCoordinator.presentMinigame(
            music: MusicCue.parse(musicName),
            memoryLabel: "gate",
            needsTutorial: { [weak self] in
                !(self?.session.hasSeenMinigameTutorial(tutorialKey) ?? true)
            },
            tutorialKey: tutorialKey,
            onTutorialAcknowledged: { [weak self] in
                self?.session.markMinigameTutorialSeen(tutorialKey)
            },
            makeDemoView: {
                GateMinigameFactory.makeDemoView(
                    config: chosen,
                    playerFx: playerFx,
                    hudConfig: hudConfig,
                    leadInSeconds: leadInSeconds
                )
            },
            makeView: { finish in
                GateMinigameFactory.makeView(
                    config: chosen,
                    playerFx: playerFx,
                    hudConfig: hudConfig,
                    vocabularySampler: self.session.vocabularySampler,
                    onFinished: finish
                )
            },
            onOutcome: { [weak self] outcome, returnToWorld in
                guard let self, let scene = self.gameScene else {
                    returnToWorld.dismissWhileCovered { $0() }
                    return
                }
                BackgroundMusicController.shared.apply(
                    MusicCue.parse(self.session.selectedLevelMusic)
                )
                switch outcome {
                case let .won(starsAwarded):
                    Task {
                        await self.session.recordStat { $0.gatesOpened += 1 }
                        await self.awardLevelStars(count: starsAwarded)
                    }
                    let prepared = scene.prepareGateEncounter(at: coord)
                    returnToWorld.crossfadeToWorld { done in
                        scene.revealGateEncounter(
                            gateNode: prepared.gateNode,
                            openedCoords: prepared.openedCoords,
                            completion: done
                        )
                    }
                case .abandoned, .lost, .none:
                    scene.prepareGateTimeout(approach: approach)
                    returnToWorld.crossfadeToWorld { done in
                        scene.revealGateTimeout(completion: done)
                    }
                }
            }
        )
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
                onResolved: { [weak self] returnToWorld in
                    returnToWorld.dismissWhileCovered { done in
                        guard let self else {
                            done()
                            return
                        }
                        self.runExitHandler.exitToLevelSelect(
                            completedLevel: true,
                            gameScene: self.gameScene,
                            session: self.session,
                            hostWindow: self.view.window
                        )
                        done()
                    }
                }
            )
        }
    }
}
