import Foundation
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
    /// Pit puzzle knobs for the selected level.
    private(set) var selectedPitConfig: PitPuzzleConfig
    /// Gate puzzle knobs for the selected level.
    private(set) var selectedGateConfig: GatePuzzleConfig
    /// Destructible-wall puzzle knobs for the selected level.
    private(set) var selectedDestructibleWallConfig: DestructibleWallPuzzleConfig
    /// Shared letter-name prompt replay interval for combat / wall / related games.
    private(set) var selectedLetterSoundRepeatSeconds: Double

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
    /// Session-scoped still background cache (screen BGs at game open).
    let backgroundLibrary: BackgroundLibrary
    /// Still frames of treasure parts for the level-select inventory row.
    let treasureIcons: SpriteIconLibrary

    init(
        appConfig: AppConfig,
        selectedLevel: LevelConfig = .fallback,
        selectedLevelName: String? = nil,
        selectedLevelResourceName: String? = nil,
        selectedLevelArtifact: String? = nil,
        selectedLevelMusic: String? = nil,
        selectedGameMusic: GameMusicConfig? = nil,
        selectedPitConfig: PitPuzzleConfig? = nil,
        selectedGateConfig: GatePuzzleConfig? = nil,
        selectedDestructibleWallConfig: DestructibleWallPuzzleConfig? = nil,
        selectedLetterSoundRepeatSeconds: Double? = nil,
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
        backgroundLibrary: BackgroundLibrary? = nil,
        treasureIcons: SpriteIconLibrary? = nil
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
        self.selectedDestructibleWallConfig = selectedDestructibleWallConfig
            ?? selectedLevel.destructibleWall
        self.selectedLetterSoundRepeatSeconds = selectedLetterSoundRepeatSeconds
            ?? selectedLevel.letterSoundRepeatSeconds
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
        self.backgroundLibrary = backgroundLibrary ?? BackgroundLibrary()
        self.treasureIcons = treasureIcons ?? SpriteIconLibrary()
    }

    /// Ensures player sprite animations are loaded for this session.
    func ensurePlayerSpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        guard let sprite = playerConfig.sprite else {
            onProgress?(1)
            return
        }
        await spriteLibrary.ensureLoaded(sprite, id: "player", onProgress: onProgress)
    }

    /// Ensures item pickup sprite animations are loaded for this session.
    ///
    /// Only the selected level's treasure part is warmed; the other seven stay unread.
    func ensureItemSpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        var requiredIDs: Set<String> = [
            PickupKind.health.rawValue,
            PickupKind.energy.rawValue,
            PickupKind.treasure.rawValue,
        ]
        if let treasureID = selectedLevel.treasure {
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
            await treasureIcons.ensureLoaded(sprite, id: id)
        }
    }

    /// Tier 0 + Tier 1 sprite ids: level-select planets, the player, and the
    /// pickups every level uses. Enemy and treasure sprites are level-scoped.
    private var persistentSpriteIDs: Set<String> {
        var ids: Set<String> = ["player", "energy", "health"]
        ids.formUnion(LevelCatalog.loadFromBundle().map(\.resourceName))
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
    func ensureEnemySpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let typeIDs = generationConfig.enemies?.types ?? []
        let spriteIDs = Set(typeIDs.compactMap { enemyConfig.enemies[$0]?.sprite })
        // Sorted so progress reporting is deterministic across launches.
        let entries = enemyConfig.sprites
            .filter { spriteIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
        guard !entries.isEmpty else {
            onProgress?(1)
            return
        }

        let total = entries.count
        for (index, entry) in entries.enumerated() {
            let start = Double(index) / Double(total)
            let end = Double(index + 1) / Double(total)
            await spriteLibrary.ensureLoaded(entry.value, id: entry.key) { local in
                onProgress?(LoadProgress.map(local, from: start, to: end))
            }
        }
        onProgress?(1)
    }

    /// Loads the baked floor tile set for the currently selected level.
    func ensureFloorTileSetLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let setName = selectedLevel.floor.set
        await floorTileSetLibrary.ensureLoaded(set: setName, onProgress: onProgress)
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

    /// Loads seed config, player store, and an unbound save service.
    ///
    /// `onProgress` receives a monotonically useful 0...1 fraction across config + floor sheets.
    static func loadResources(
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> AppSession {
        func report(_ value: Double) async {
            onProgress?(value)
            await Task.yield()
        }

        // Config / store bootstrap occupies the first slice; UI planets then floor sheets fill the rest.
        let configEnd = 0.18

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
        await report(0.03)

        let soundSettings = ConfigStore.loadOrFallback("audio", fallback: SoundSettings.fallback) {
            let loaded = try SoundSettings.loadFromBundle()
            try loaded.validate()
            return loaded
        }
        BackgroundMusicController.shared.configure(fadeSeconds: soundSettings.fadeSeconds)
        SoundEffectsController.shared.configure(commonFx: soundSettings.fx)
        AudioPreferences.shared.applyToControllers()
        await report(0.06)

        let playerConfig = ConfigStore.loadOrFallback("player", fallback: PlayerConfig.fallback) {
            let loaded = try PlayerConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        }

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
        await report(0.14)

        await report(configEnd)

        let spriteLibrary = SpriteLibrary()
        let backgroundLibrary = BackgroundLibrary()
        // Level-select planet art: load at game open so the picker has sprites ready.
        let uiEntries = LevelCatalog.loadFromBundle().compactMap { level -> (String, SpriteConfig)? in
            guard let sprite = level.sprite else { return nil }
            return (level.resourceName, sprite)
        }
        let uiEnd = uiEntries.isEmpty ? configEnd : 0.26
        if !uiEntries.isEmpty {
            let total = uiEntries.count
            for (index, entry) in uiEntries.enumerated() {
                let start = LoadProgress.map(Double(index) / Double(total), from: configEnd, to: uiEnd)
                let end = LoadProgress.map(Double(index + 1) / Double(total), from: configEnd, to: uiEnd)
                await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
            }
        }
        await report(uiEnd)

        // All screen backgrounds referenced by screens.yaml.
        let screenBackgroundNames = BackgroundLibrary.screenBackgroundNames()
        let backgroundsEnd = screenBackgroundNames.isEmpty ? uiEnd : 0.32
        await backgroundLibrary.ensureLoaded(names: screenBackgroundNames) { local in
            onProgress?(LoadProgress.map(local, from: uiEnd, to: backgroundsEnd))
        }
        await report(backgroundsEnd)

        // Floor sets are per-level; load when a level is selected / launched.
        let floorTileSetLibrary = FloorTileSetLibrary()
        await report(1)

        do {
            let levels = try LevelCatalog.loadFromBundle().map { descriptor in
                try LevelConfig.loadFromBundle(
                    named: descriptor.resourceName,
                    subdirectory: LevelCatalog.subdirectory,
                    wordCatalog: wordCatalog,
                    letterCatalog: letterCatalog
                )
            }
            try ConfigAudit.run(
                app: appConfig,
                levels: levels,
                enemies: enemyConfig,
                items: itemsConfig,
                words: wordCatalog,
                letters: letterCatalog,
                audio: soundSettings,
                screens: screensConfig,
                player: playerConfig
            )
        } catch {
            assertionFailure("ConfigAudit failed: \(error)")
        }

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
            backgroundLibrary: backgroundLibrary
        )
    }

    func selectLevel(resourceName: String) throws {
        let loaded = try WorldLoader.loadConfigAndLevelFromBundle(
            levelNamed: resourceName,
            levelSubdirectory: LevelCatalog.subdirectory
        )
        try loaded.config.validate()
        appConfig = loaded.config
        applySelectedLevel(loaded.level, resourceName: resourceName)
    }

    private func applySelectedLevel(_ level: LevelConfig, resourceName: String?) {
        selectedLevel = level
        selectedLevelName = level.name
        selectedLevelResourceName = resourceName
        selectedLevelArtifact = level.artifact
        selectedLevelMusic = level.music
        selectedGameMusic = level.gameMusic
        selectedPitConfig = level.pit
        selectedGateConfig = level.gate
        selectedDestructibleWallConfig = level.destructibleWall
        selectedLetterSoundRepeatSeconds = level.letterSoundRepeatSeconds
    }

    func bindPlayer(name: String) async throws {
        let trimmed = PlayerStateStore.normalizedName(name)
        let state = try await playerStore.loadState(for: trimmed)
        let playerSaveService = try await playerStore.makeSaveService(for: trimmed)

        currentPlayerName = trimmed
        playerState = state
        saveService = playerSaveService
        audioPreferences.apply(state.settings)

        if let lastLevel = state.lastLevelStarted {
            try? selectLevel(resourceName: lastLevel)
        }

        await refreshContinueEligibility()
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
        guard var state = playerState else { return }
        state.resetForNewGame(
            health: playerConfig.startingHealth,
            energy: playerConfig.startingEnergy
        )
        playerState = state
        await persistPlayerState()
        try? await saveService.delete()
        await refreshContinueEligibility()
    }

    func markLevelStarted(resourceName: String) async {
        playerState?.markLevelStarted(resourceName)
        selectedLevelResourceName = resourceName
        await persistPlayerState()
    }

    func markLevelCompleted(resourceName: String) async {
        playerState?.markLevelCompleted(resourceName, artifact: selectedLevelArtifact)
        await persistPlayerState()
    }

    var isDadModeUnlocked: Bool {
        playerState?.dadModeUnlocked ?? false
    }

    func unlockDadMode() async {
        guard var state = playerState else { return }
        state.dadModeUnlocked = true
        playerState = state
        await persistPlayerState()
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
