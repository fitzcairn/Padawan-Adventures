import Foundation
import SpriteKit
import UIKit

/// Shared bootstrap state loaded before the menu appears.
@MainActor
final class AppSession {
    private var memoryWarningObserver: NSObjectProtocol?
    private(set) var appConfig: AppConfig
    /// Full selected level (map size, generation, floors, puzzles, music, …).
    private(set) var selectedLevel: LevelConfig
    private(set) var selectedLevelName: String
    private(set) var selectedLevelResourceName: String?
    /// SF Symbol name awarded to inventory when this level is completed.
    private(set) var selectedLevelArtifact: String
    /// Raw level `music:` value for the selected level.
    private(set) var selectedLevelMusic: String?
    /// Per-minigame music for the selected level.
    private(set) var selectedGameMusic: GameMusicConfig
    /// Pit minigame variants + weights for the selected level.
    private(set) var selectedPitConfig: PitConfig
    /// Gate config (host FX + minigames list) for the selected level.
    private(set) var selectedGateConfig: GateConfig
    /// Combat minigame variants + weights for the selected level.
    private(set) var selectedCombatConfig: CombatConfig
    /// Shared letter-name prompt replay interval for combat / wall / related games.
    private(set) var selectedLetterSoundRepeatSeconds: Double
    /// Combat letter spawn frequency multiplier for the selected level.
    private(set) var selectedCombatLetterSpawnRate: Double
    /// Combat letter casing for the selected level.
    private(set) var selectedCombatLetterCase: CombatLetterCase

    /// App + level knobs for procedural generation / save-size checks.
    var generationConfig: WorldGenerationConfig {
        .compose(app: appConfig, level: selectedLevel)
    }
    let playerConfig: PlayerConfig
    let enemyConfig: EnemyConfig
    let itemsConfig: ItemsConfig
    let playerStore: PlayerStateStore
    private(set) var saveService: GameSaveService
    private(set) var hasCompatibleSave: Bool
    private(set) var currentPlayerName: String?
    private(set) var playerState: PlayerGameState?
    let audioPreferences: AudioPreferences
    /// Session-scoped sprite animation cache (sheets sliced once per process).
    let spriteLibrary: SpriteLibrary
    /// Session-scoped cache of the active level's baked floor tile set.
    let floorTileSetLibrary: FloorTileSetLibrary
    /// Session-scoped cache of the active level's baked letter glyph set.
    let letterSpriteSetLibrary: LetterSpriteSetLibrary
    /// Session-scoped cache of the active level's baked pit platform tile set.
    let pitSpriteSetLibrary: PitSpriteSetLibrary
    /// Session-scoped cache of the active level's baked world gate wall sprites.
    let gateSpriteSetLibrary: GateSpriteSetLibrary
    /// Session-scoped still background cache (screen BGs at game open).
    let backgroundLibrary: BackgroundLibrary
    /// Session-scoped cutscene movie, preloaded so NEW GAME can start playback immediately.
    let cutsceneVideo: CutsceneVideo
    /// Enemy sprite ids warmed at bootstrap for every playable level; kept across levels.
    private let retainedEnemySpriteIDs: Set<String>
    /// Resource name of a level first-completed this session; level select consumes it for unlock FX.
    private(set) var pendingLevelSelectCelebration: String? = nil

    init(
        appConfig: AppConfig,
        selectedLevel: LevelConfig = .fallback,
        selectedLevelName: String? = nil,
        selectedLevelResourceName: String? = nil,
        selectedLevelArtifact: String? = nil,
        selectedLevelMusic: String? = nil,
        selectedGameMusic: GameMusicConfig? = nil,
        selectedPitConfig: PitConfig? = nil,
        selectedGateConfig: GateConfig? = nil,
        selectedCombatConfig: CombatConfig? = nil,
        selectedLetterSoundRepeatSeconds: Double? = nil,
        selectedCombatLetterSpawnRate: Double? = nil,
        selectedCombatLetterCase: CombatLetterCase? = nil,
        playerConfig: PlayerConfig? = nil,
        enemyConfig: EnemyConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        playerStore: PlayerStateStore,
        saveService: GameSaveService,
        hasCompatibleSave: Bool = false,
        currentPlayerName: String? = nil,
        playerState: PlayerGameState? = nil,
        audioPreferences: AudioPreferences? = nil,
        spriteLibrary: SpriteLibrary? = nil,
        floorTileSetLibrary: FloorTileSetLibrary? = nil,
        letterSpriteSetLibrary: LetterSpriteSetLibrary? = nil,
        pitSpriteSetLibrary: PitSpriteSetLibrary? = nil,
        gateSpriteSetLibrary: GateSpriteSetLibrary? = nil,
        backgroundLibrary: BackgroundLibrary? = nil,
        cutsceneVideo: CutsceneVideo? = nil,
        retainedEnemySpriteIDs: Set<String> = []
    ) {
        self.appConfig = appConfig
        self.selectedLevel = selectedLevel
        self.selectedLevelName = selectedLevelName ?? selectedLevel.name
        self.selectedLevelResourceName = selectedLevelResourceName
        self.selectedLevelArtifact = selectedLevelArtifact ?? selectedLevel.artifact
        self.selectedLevelMusic = selectedLevelMusic ?? selectedLevel.music
        self.selectedGameMusic = selectedGameMusic ?? selectedLevel.gameMusic
        self.selectedPitConfig = selectedPitConfig ?? selectedLevel.pit
        self.selectedGateConfig = selectedGateConfig ?? selectedLevel.gate
        self.selectedCombatConfig = selectedCombatConfig ?? selectedLevel.combat
        self.selectedLetterSoundRepeatSeconds = selectedLetterSoundRepeatSeconds
            ?? selectedLevel.letterSoundRepeatSeconds
        self.selectedCombatLetterSpawnRate = selectedCombatLetterSpawnRate
            ?? selectedLevel.combatLetterSpawnRate
        self.selectedCombatLetterCase = selectedCombatLetterCase
            ?? selectedLevel.combatLetterCase
        // Default-argument expressions are nonisolated; resolve MainActor defaults in-body.
        self.playerConfig = playerConfig ?? .fallback
        self.enemyConfig = enemyConfig ?? .fallback
        self.itemsConfig = itemsConfig ?? .fallback
        self.playerStore = playerStore
        self.saveService = saveService
        self.hasCompatibleSave = hasCompatibleSave
        self.currentPlayerName = currentPlayerName
        self.playerState = playerState
        self.audioPreferences = audioPreferences ?? .shared
        self.spriteLibrary = spriteLibrary ?? SpriteLibrary()
        self.floorTileSetLibrary = floorTileSetLibrary ?? FloorTileSetLibrary()
        self.letterSpriteSetLibrary = letterSpriteSetLibrary ?? LetterSpriteSetLibrary()
        self.pitSpriteSetLibrary = pitSpriteSetLibrary ?? PitSpriteSetLibrary()
        self.gateSpriteSetLibrary = gateSpriteSetLibrary ?? GateSpriteSetLibrary()
        self.backgroundLibrary = backgroundLibrary ?? BackgroundLibrary()
        self.cutsceneVideo = cutsceneVideo ?? CutsceneVideo()
        self.retainedEnemySpriteIDs = retainedEnemySpriteIDs
    }

    /// Ensures player sprite animations are loaded for this session.
    func ensurePlayerSpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        if let sprite = playerConfig.sprite {
            await spriteLibrary.ensureLoaded(sprite, id: "player", onProgress: onProgress)
        }
        if let combat = playerConfig.combatSprite {
            await spriteLibrary.ensureLoaded(combat, id: "player_combat")
        }
        if playerConfig.sprite == nil {
            onProgress?(1)
        }
    }

    /// Ensures item pickup sprite animations are loaded for this session.
    ///
    /// By default warms shared pickups plus every level treasure part (bootstrapped at load).
    func ensureItemSpritesLoaded(
        includeAllTreasures: Bool = true,
        onProgress: ((Double) -> Void)? = nil
    ) async {
        var requiredIDs: Set<String> = [
            PickupKind.health.rawValue,
            PickupKind.energy.rawValue,
            PickupKind.treasure.rawValue,
        ]
        if includeAllTreasures {
            requiredIDs.formUnion(LevelCatalog.loadFromBundle().compactMap(\.treasure))
        } else if let treasureID = selectedLevel.treasure {
            requiredIDs.insert(treasureID)
        }

        let entries = itemsConfig.items
            .filter { requiredIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
            .compactMap { id, item -> (String, SpriteConfig)? in
                guard let sprite = item.sprite else { return nil }
                return (id, sprite)
            }
        guard !entries.isEmpty else {
            onProgress?(1)
            return
        }

        let total = entries.count
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
        }
        onProgress?(1)
    }

    /// Warms level-select inventory icons for the given treasure item ids.
    func ensureTreasureIconsLoaded(ids: [String]) async {
        for id in ids {
            guard let sprite = itemsConfig.spriteConfig(id: id) else { continue }
            await spriteLibrary.ensureLoaded(sprite, id: id)
        }
    }

    /// Tier 0 + Tier 1 sprite ids warmed at bootstrap and kept across levels.
    private var persistentSpriteIDs: Set<String> {
        var ids: Set<String> = [
            "player",
            "player_combat",
            "energy",
            "health",
            "coin",
            "treasure",
            "logo",
            "kam",
            "yoda",
        ]
        let levels = LevelCatalog.loadFromBundle()
        ids.formUnion(levels.map(\.resourceName))
        ids.formUnion(levels.compactMap(\.treasure))
        ids.formUnion(retainedEnemySpriteIDs)
        return ids
    }

    /// Frees enemy and per-level treasure textures after leaving a level.
    func releaseLevelScopedSprites() {
        spriteLibrary.retain(ids: persistentSpriteIDs)
    }

    /// Drops level-scoped textures under memory pressure.
    ///
    /// Safe outside a level; during play the enemy sprites are in use, so this is
    /// registered only while no game is presented.
    func startObservingMemoryPressure() {
        guard memoryWarningObserver == nil else { return }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.releaseLevelScopedSprites()
            }
        }
    }

    func stopObservingMemoryPressure() {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        memoryWarningObserver = nil
    }

    /// Ensures enemy sprite animations for the selected level's spawn list are loaded.
    ///
    /// Scoped rather than loading every catalog sprite: the full set is ~160 sheets.
    /// Returns `false` if any sprite is still incomplete after one retry — callers must
    /// not present the level until this returns `true`.
    @discardableResult
    func ensureEnemySpritesLoaded(onProgress: ((Double) -> Void)? = nil) async -> Bool {
        let typeIDs = generationConfig.enemies?.types ?? []
        let spriteIDs = Set(typeIDs.compactMap { enemyConfig.enemies[$0]?.sprite })
        // Sorted so progress reporting is deterministic across launches.
        let entries = enemyConfig.sprites
            .filter { spriteIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
        guard !entries.isEmpty else {
            onProgress?(1)
            return true
        }

        let total = entries.count
        var allReady = true
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            func reportLocal(_ local: Double) {
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
            await spriteLibrary.ensureLoaded(entry.value, id: entry.key, onProgress: reportLocal)
            if !spriteLibrary.isLoaded(id: entry.key) {
                await spriteLibrary.ensureLoaded(entry.value, id: entry.key, onProgress: reportLocal)
            }
            if !spriteLibrary.isLoaded(id: entry.key) {
                let missing = spriteLibrary.missingAnimations(id: entry.key, config: entry.value)
                GameLogger.error(
                    .sprites,
                    "enemy sprite '\(entry.key)' incomplete after retry — missing \(missing.joined(separator: ", "))"
                )
                allReady = false
            }
        }
        onProgress?(1)
        return allReady
    }

    /// Loads the baked floor tile set for the currently selected level.
    func ensureFloorTileSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.floor.set
        await floorTileSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Loads the baked letter glyph set for the currently selected level.
    func ensureLetterSpriteSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.letters.set
        await letterSpriteSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Loads the baked pit platform tile set for the currently selected level.
    /// Uses the same set name as the level floor set (`1-tython`, …).
    func ensurePitSpriteSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.floor.set
        await pitSpriteSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Loads the baked world gate wall sprites for the currently selected level.
    /// Uses the same set name as the level floor set (`1-tython`, …).
    func ensureGateSpriteSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.floor.set
        await gateSpriteSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
    }

    /// Ensures level-select planet sprites are loaded for this session.
    func ensureUISpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let entries = LevelCatalog.loadFromBundle().compactMap { level -> (String, SpriteConfig)? in
            guard let sprite = level.sprite else { return nil }
            return (level.resourceName, sprite)
        }
        guard !entries.isEmpty else {
            onProgress?(1)
            return
        }

        let total = entries.count
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
        }
        onProgress?(1)
    }

    nonisolated static func fallbackAppConfig() -> AppConfig {
        AppConfig(
            version: 1,
            seed: nil,
            world: AppConfig.WorldSize(stories: 1),
            display: AppConfig.DisplayParams(tileWidth: 40, tileHeight: 40)
        )
    }

    /// Backward-compatible alias used by older test helpers.
    nonisolated static func fallbackConfig() -> AppConfig {
        fallbackAppConfig()
    }

    /// Loads config, stores, and warms screen + shared gameplay assets before tap-to-start.
    ///
    /// Call after the loading screen has already warmed title art into `spriteLibrary`.
    /// `onProgress` receives a monotonically useful 0...1 fraction for this phase only.
    static func loadResources(
        spriteLibrary: SpriteLibrary? = nil,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> AppSession {
        func report(_ value: Double) async {
            onProgress?(value)
            await Task.yield()
        }

        GameLogger.mark(.session, "loadResources begin")
        let spriteLibrary = spriteLibrary ?? SpriteLibrary()

        // Ensure title art is present when callers (tests) skip the LoadingView phase.
        if spriteLibrary.uiImage(id: "logo") == nil,
           let loadingSprites = try? LoadingSpritesConfig.loadFromBundle() {
            for entry in loadingSprites.entries {
                await spriteLibrary.ensureLoaded(entry.config, id: entry.id)
            }
            _ = spriteLibrary.uiImage(id: "logo")
            _ = spriteLibrary.uiImages(id: "kam")
            _ = spriteLibrary.uiImages(id: "yoda")
        }
        await report(0.02)

        // Config / store bootstrap, then remaining screen + gameplay assets.
        let configEnd = 0.14

        // Start title music early so it is audible during the rest of bootstrap.
        let soundSettings = ConfigStore.loadOrFallback("audio", fallback: SoundSettings.fallback) {
            let loaded = try SoundSettings.loadFromBundle()
            try loaded.validate()
            return loaded
        }
        BackgroundMusicController.shared.configure(fadeSeconds: soundSettings.fadeSeconds)
        SoundEffectsController.shared.configure(commonFx: soundSettings.fx)
        AudioPreferences.shared.applyToControllers()
        BackgroundMusicController.shared.applyScreen(named: "loading")
        await report(0.04)

        let appAndLevel = ConfigStore.loadOrFallback(
            "app+level",
            fallback: (fallbackAppConfig(), LevelConfig.fallback)
        ) { () -> (AppConfig, LevelConfig) in
            let loaded = try WorldLoader.loadConfigAndLevelFromBundle()
            try loaded.config.validate()
            return (loaded.config, loaded.level)
        }
        let appConfig = appAndLevel.0
        let selectedLevel = appAndLevel.1
        GameLogger.mark(
            .config,
            "bootstrap level '\(selectedLevel.name)' loaded (combat: \(selectedLevel.combat.minigames.map(\.kind.rawValue).joined(separator: "/")))"
        )
        await report(0.06)

        let playerConfig = ConfigStore.loadOrFallback("player", fallback: PlayerConfig.fallback) {
            let loaded = try PlayerConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        }
        // Warm shared + player FX so the first gameplay cue does not decode on the main thread.
        var warmTrackIDs = Array(soundSettings.fx.events.values)
        warmTrackIDs.append(contentsOf: playerConfig.fx.events.values)
        SoundEffectsController.shared.prepare(trackIDs: warmTrackIDs)

        let enemyConfig = ConfigStore.loadOrFallback("enemies", fallback: EnemyConfig.fallback) {
            let loaded = try EnemyConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        let itemsConfig = ConfigStore.loadOrFallback("items", fallback: ItemsConfig.fallback) {
            let loaded = try ItemsConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        let screensConfig = ConfigStore.loadOrFallback("screens", fallback: ScreensConfig.fallback) {
            try ScreensConfig.loadFromBundle()
        }

        let wordCatalog = ConfigStore.loadOrFallback("words", fallback: WordCatalog.fallback) {
            let loaded = try WordCatalog.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        let letterCatalog = ConfigStore.loadOrFallback("letters", fallback: LetterCatalog.fallback) {
            let loaded = try LetterCatalog.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        await report(0.10)

        let playerStore: PlayerStateStore
        let saveService: GameSaveService
        if let store = try? PlayerStateStore() {
            playerStore = store
            // Unbound placeholder until a player is selected; directory is the store root.
            saveService = (try? GameSaveService(directoryURL: store.rootDirectoryURL))
                ?? (try! GameSaveService(directoryURL: FileManager.default.temporaryDirectory))
        } else {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("PadawanAdventures", isDirectory: true)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            playerStore = try! PlayerStateStore(directoryURL: temp)
            saveService = try! GameSaveService(directoryURL: temp)
        }

        try? await playerStore.purgeOrphans()
        await report(configEnd)

        let backgroundLibrary = BackgroundLibrary()
        let levelDescriptors = LevelCatalog.loadFromBundle()

        // 1) Level-select planet art (+ upright UIImages for first paint).
        let uiEntries = levelDescriptors.compactMap { level -> (String, SpriteConfig)? in
            guard let sprite = level.sprite else { return nil }
            return (level.resourceName, sprite)
        }
        let planetsEnd = uiEntries.isEmpty ? configEnd : 0.28
        if !uiEntries.isEmpty {
            let total = uiEntries.count
            for (index, entry) in uiEntries.enumerated() {
                let start = LoadProgress.map(Double(index) / Double(total), from: configEnd, to: planetsEnd)
                let end = LoadProgress.map(Double(index + 1) / Double(total), from: configEnd, to: planetsEnd)
                await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
                _ = spriteLibrary.uiImage(id: entry.0, named: "idle")
            }
        }
        await report(planetsEnd)

        // 2) Screen backgrounds from screens.yaml.
        let screenBackgroundNames = BackgroundLibrary.screenBackgroundNames()
        let backgroundsEnd = screenBackgroundNames.isEmpty ? planetsEnd : 0.40
        await backgroundLibrary.ensureLoaded(names: screenBackgroundNames) { local in
            onProgress?(LoadProgress.map(local, from: planetsEnd, to: backgroundsEnd))
        }
        await report(backgroundsEnd)

        // 2b) Cutscene movie + characters, so NEW GAME opens on a running video.
        let cutsceneVideo = CutsceneVideo()
        let cutsceneEnd = 0.46
        await cutsceneVideo.preload()
        if let cutsceneSprites = try? CutsceneSpritesConfig.loadFromBundle() {
            let total = max(cutsceneSprites.entries.count, 1)
            for (index, entry) in cutsceneSprites.entries.enumerated() {
                let start = LoadProgress.map(
                    Double(index) / Double(total), from: backgroundsEnd, to: cutsceneEnd
                )
                let end = LoadProgress.map(
                    Double(index + 1) / Double(total), from: backgroundsEnd, to: cutsceneEnd
                )
                await spriteLibrary.ensureLoaded(entry.config, id: entry.id) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
                _ = spriteLibrary.uiImages(id: entry.id)
            }
        }
        await report(cutsceneEnd)

        // 3) (Treasure / coin / HUD icons seed after item sprites load in step 5.)
        let treasureIDs = levelDescriptors.compactMap(\.treasure)
        let iconsEnd = cutsceneEnd
        await report(iconsEnd)

        // 4) Player walk / combat sprites.
        let playerEnd = 0.58
        if let sprite = playerConfig.sprite {
            await spriteLibrary.ensureLoaded(sprite, id: "player") { local in
                onProgress?(LoadProgress.map(local, from: iconsEnd, to: 0.54))
            }
        }
        if let combat = playerConfig.combatSprite {
            await spriteLibrary.ensureLoaded(combat, id: "player_combat") { local in
                onProgress?(LoadProgress.map(local, from: 0.54, to: playerEnd))
            }
        }
        await report(playerEnd)

        // 5) Shared pickups + coin + every level treasure part animation.
        var itemIDs: Set<String> = [
            PickupKind.health.rawValue,
            PickupKind.energy.rawValue,
            PickupKind.treasure.rawValue,
            "coin",
        ]
        itemIDs.formUnion(treasureIDs)
        let itemEntries = itemsConfig.items
            .filter { itemIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
            .compactMap { id, item -> (String, SpriteConfig)? in
                guard let sprite = item.sprite else { return nil }
                return (id, sprite)
            }
        let itemsEnd = itemEntries.isEmpty ? playerEnd : 0.70
        if !itemEntries.isEmpty {
            let total = itemEntries.count
            for (index, entry) in itemEntries.enumerated() {
                let start = LoadProgress.map(Double(index) / Double(total), from: playerEnd, to: itemsEnd)
                let end = LoadProgress.map(Double(index + 1) / Double(total), from: playerEnd, to: itemsEnd)
                await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
            }
        }
        ScoreCoinIcon.seed(spriteLibrary.uiImage(id: "coin"))
        HudVitalIcon.health.seed(spriteLibrary.uiImage(id: "health"))
        HudVitalIcon.energy.seed(spriteLibrary.uiImage(id: "energy"))
        await report(itemsEnd)

        // 6) Enemy sprites used by any playable level (not the entire unused catalog).
        let levelsForAudit: [LevelConfig]
        do {
            levelsForAudit = try levelDescriptors.map { descriptor in
                try LevelConfig.loadFromBundle(
                    named: descriptor.resourceName,
                    subdirectory: LevelCatalog.subdirectory,
                    wordCatalog: wordCatalog,
                    letterCatalog: letterCatalog
                )
            }
        } catch {
            levelsForAudit = [selectedLevel]
            GameLogger.fault(.config, "failed to load levels during bootstrap: \(error)")
            assertionFailure("Failed to load levels during bootstrap: \(error)")
        }

        var enemySpriteIDs = Set<String>()
        for level in levelsForAudit {
            for typeID in level.enemies?.types ?? [] {
                if let spriteID = enemyConfig.enemies[typeID]?.sprite {
                    enemySpriteIDs.insert(spriteID)
                }
            }
        }
        let enemyEntries = enemyConfig.sprites
            .filter { enemySpriteIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
        let enemiesEnd = enemyEntries.isEmpty ? itemsEnd : 0.92
        if !enemyEntries.isEmpty {
            let total = enemyEntries.count
            for (index, entry) in enemyEntries.enumerated() {
                let start = LoadProgress.map(Double(index) / Double(total), from: itemsEnd, to: enemiesEnd)
                let end = LoadProgress.map(Double(index + 1) / Double(total), from: itemsEnd, to: enemiesEnd)
                await spriteLibrary.ensureLoaded(entry.value, id: entry.key) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
            }
        }
        await report(enemiesEnd)

        // 7) Gate minigame stills + GPU upload for every warmed texture.
        var gateTextures = GateMinigameBackground.preloadTextures()
        if let capacitor = GateSpellingCapacitorSprites.load() {
            gateTextures.append(capacitor)
        }
        if let switches = GateLetterMatchSwitchSprites.load() {
            gateTextures.append(switches.off)
            gateTextures.append(switches.on)
        }
        let preloadTextures = spriteLibrary.allTextures() + gateTextures
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SKTexture.preload(preloadTextures) {
                continuation.resume()
            }
        }
        await report(1)

        // Floor / letter / pit / gate sets stay per-level (single active set in each library).
        let floorTileSetLibrary = FloorTileSetLibrary()
        let letterSpriteSetLibrary = LetterSpriteSetLibrary()
        let pitSpriteSetLibrary = PitSpriteSetLibrary()
        let gateSpriteSetLibrary = GateSpriteSetLibrary()

        do {
            try ConfigAudit.run(
                app: appConfig,
                levels: levelsForAudit,
                enemies: enemyConfig,
                items: itemsConfig,
                words: wordCatalog,
                letters: letterCatalog,
                audio: soundSettings,
                screens: screensConfig,
                player: playerConfig
            )
        } catch {
            GameLogger.fault(.config, "ConfigAudit failed: \(error)")
            assertionFailure("ConfigAudit failed: \(error)")
        }
        GameLogger.mark(.session, "loadResources complete")

        return AppSession(
            appConfig: appConfig,
            selectedLevel: selectedLevel,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            itemsConfig: itemsConfig,
            playerStore: playerStore,
            saveService: saveService,
            hasCompatibleSave: false,
            spriteLibrary: spriteLibrary,
            floorTileSetLibrary: floorTileSetLibrary,
            letterSpriteSetLibrary: letterSpriteSetLibrary,
            pitSpriteSetLibrary: pitSpriteSetLibrary,
            gateSpriteSetLibrary: gateSpriteSetLibrary,
            backgroundLibrary: backgroundLibrary,
            cutsceneVideo: cutsceneVideo,
            retainedEnemySpriteIDs: enemySpriteIDs
        )
    }

    func selectLevel(resourceName: String) throws {
        try GameLogger.step(.session, "selectLevel(\(resourceName))") {
            let loaded = try WorldLoader.loadConfigAndLevelFromBundle(
                levelNamed: resourceName,
                levelSubdirectory: LevelCatalog.subdirectory
            )
            try loaded.config.validate()
            appConfig = loaded.config
            applySelectedLevel(loaded.level, resourceName: resourceName)
        }
    }

    private func applySelectedLevel(_ level: LevelConfig, resourceName: String?) {
        GameLogger.mark(
            .session,
            """
            applySelectedLevel '\(level.name)' \
            (combat: \(level.combat.minigames.map(\.kind.rawValue).joined(separator: "/")), \
            gate: \(level.gate.minigames.count) minigames)
            """
        )
        selectedLevel = level
        selectedLevelName = level.name
        selectedLevelResourceName = resourceName
        selectedLevelArtifact = level.artifact
        selectedLevelMusic = level.music
        selectedGameMusic = level.gameMusic
        selectedPitConfig = level.pit
        selectedGateConfig = level.gate
        selectedCombatConfig = level.combat
        selectedLetterSoundRepeatSeconds = level.letterSoundRepeatSeconds
        selectedCombatLetterSpawnRate = level.combatLetterSpawnRate
        selectedCombatLetterCase = level.combatLetterCase
    }

    func bindPlayer(name: String) async throws {
        // Player names are user data and deliberately kept out of the log.
        try await GameLogger.step(.session, "bindPlayer") {
            let trimmed = PlayerStateStore.normalizedName(name)
            let state = try await playerStore.loadState(for: trimmed)
            let playerSaveService = try await playerStore.makeSaveService(for: trimmed)

            currentPlayerName = trimmed
            playerState = state
            saveService = playerSaveService
            audioPreferences.apply(state.settings)

            if let lastLevel = state.lastLevelStarted {
                GameLogger.mark(.session, "restoring last level '\(lastLevel)'")
                do {
                    try selectLevel(resourceName: lastLevel)
                } catch {
                    GameLogger.error(
                        .session,
                        "could not restore '\(lastLevel)': \(error); keeping bootstrap level"
                    )
                }
            }

            await refreshContinueEligibility()
        }
    }

    /// Copies the live Settings values into the bound player's persisted state.
    func persistCurrentSettings() async {
        guard playerState != nil else { return }
        playerState?.settings = audioPreferences.snapshot
        await persistPlayerState()
    }

    func createAndBindPlayer(name: String) async throws {
        let trimmed = PlayerStateStore.normalizedName(name)
        let initial = PlayerGameState(
            health: playerConfig.startingHealth,
            energy: playerConfig.startingEnergy
        )
        try await playerStore.createPlayer(name: trimmed, initialState: initial)
        try await bindPlayer(name: trimmed)
    }

    func deletePlayer(name: String) async throws {
        let trimmed = PlayerStateStore.normalizedName(name)
        try await playerStore.deletePlayer(name: trimmed)
        if currentPlayerName == trimmed {
            currentPlayerName = nil
            playerState = nil
            hasCompatibleSave = false
        }
    }

    func persistPlayerState() async {
        guard let name = currentPlayerName, let state = playerState else { return }
        try? await playerStore.saveState(state, for: name)
    }

    func syncVitals(from world: GameWorld) async {
        guard playerState != nil else { return }
        playerState?.syncVitals(from: world)
        await persistPlayerState()
    }

    /// Restores health/energy to `player.yaml` starting values for a new game.
    func resetVitalsToStarting() async {
        guard playerState != nil else { return }
        playerState?.resetVitals(
            health: playerConfig.startingHealth,
            energy: playerConfig.startingEnergy
        )
        await persistPlayerState()
    }

    /// Starts a fresh game: empty inventory, zero stars, default vitals, no mid-run save.
    func beginNewGame() async {
        await GameLogger.step(.session, "beginNewGame") {
            guard var state = playerState else {
                GameLogger.error(.session, "beginNewGame with no bound player; ignoring")
                return
            }
            state.resetForNewGame(
                health: playerConfig.startingHealth,
                energy: playerConfig.startingEnergy
            )
            playerState = state
            pendingLevelSelectCelebration = nil
            await persistPlayerState()
            do {
                try await saveService.delete()
            } catch {
                GameLogger.error(.session, "could not delete mid-run save: \(error)")
            }
            await refreshContinueEligibility()
        }
    }

    func markLevelStarted(resourceName: String) async {
        playerState?.markLevelStarted(resourceName)
        selectedLevelResourceName = resourceName
        await persistPlayerState()
    }

    func markLevelCompleted(resourceName: String) async {
        let wasCompleted = playerState?.levels[resourceName]?.completed == true
        playerState?.markLevelCompleted(resourceName, artifact: selectedLevelArtifact)
        if !wasCompleted {
            pendingLevelSelectCelebration = resourceName
        }
        await persistPlayerState()
    }

    /// Returns and clears the pending level-select unlock celebration, if any.
    func consumeLevelSelectCelebration() -> String? {
        let resourceName = pendingLevelSelectCelebration
        pendingLevelSelectCelebration = nil
        return resourceName
    }

    var isDadModeUnlocked: Bool {
        playerState?.dadModeUnlocked ?? false
    }

    @discardableResult
    func unlockDadMode() async -> Bool {
        guard var state = playerState else { return false }
        state.dadModeUnlocked = true
        playerState = state
        await persistPlayerState()
        return true
    }

    /// Grants artifacts / completion for all catalog levels before `resourceName`, clears Dad mode, persists.
    func applyDadModeProgression(to resourceName: String) async {
        guard var state = playerState else { return }
        let ordered = LevelCatalog.loadFromBundle().map(\.resourceName)
        var artifactsByResource: [String: String] = [:]
        for name in ordered {
            if let level = try? LevelConfig.loadFromBundle(
                named: name,
                subdirectory: LevelCatalog.subdirectory
            ) {
                artifactsByResource[name] = level.artifact
            }
        }
        state.applyProgressionJump(
            upTo: resourceName,
            orderedLevels: ordered,
            artifactsByResource: artifactsByResource
        )
        playerState = state
        await persistPlayerState()
    }

    func resetLevelStarsCurrent(resourceName: String) async {
        guard playerState != nil else { return }
        playerState?.resetLevelStarsCurrent(resourceName)
        await persistPlayerState()
    }

    func addLevelStar(resourceName: String) async {
        await addLevelStars(resourceName: resourceName, count: 1)
    }

    func addLevelStars(resourceName: String, count: Int) async {
        guard playerState != nil, count > 0 else { return }
        playerState?.addLevelStars(resourceName, count: count)
        await persistPlayerState()
    }

    @discardableResult
    func finalizeLevelStars(resourceName: String) async -> LevelStarsFinalizeResult? {
        guard var state = playerState else { return nil }
        let result = state.finalizeLevelStars(resourceName)
        playerState = state
        await persistPlayerState()
        return result
    }

    func recordStat(_ update: (inout PlayerStats) -> Void) async {
        guard var state = playerState else { return }
        update(&state.stats)
        playerState = state
        await persistPlayerState()
    }

    nonisolated static func isContinueEligible(
        savedWorld: GameWorld?,
        config: WorldGenerationConfig
    ) -> Bool {
        guard let savedWorld else { return false }
        return WorldLoader.isCompatibleSave(savedWorld, with: config)
    }

    func refreshContinueEligibility() async {
        guard currentPlayerName != nil else {
            hasCompatibleSave = false
            return
        }

        var generation = generationConfig
        if let lastLevel = playerState?.lastLevelStarted {
            if let loaded = try? WorldLoader.loadConfigAndLevelFromBundle(
                levelNamed: lastLevel,
                levelSubdirectory: LevelCatalog.subdirectory
            ) {
                generation = .compose(app: loaded.config, level: loaded.level)
            }
        }

        hasCompatibleSave = await Self.probeCompatibleSave(
            saveService: saveService,
            config: generation
        )
    }

    private static func probeCompatibleSave(
        saveService: GameSaveService,
        config: WorldGenerationConfig
    ) async -> Bool {
        do {
            let saved = try await saveService.load()
            return isContinueEligible(savedWorld: saved, config: config)
        } catch {
            return false
        }
    }
}

enum GameLaunchMode: Hashable, Sendable {
    case continueSave
    case newGame
}
