import Foundation

/// Shared bootstrap state loaded before the menu appears.
@MainActor
final class AppSession {
    private(set) var seedConfig: WorldSeedConfig
    private(set) var selectedLevelName: String
    private(set) var selectedLevelResourceName: String?
    /// SF Symbol name awarded to inventory when this level is completed.
    private(set) var selectedLevelArtifact: String
    /// Raw level `music:` value for the selected level.
    private(set) var selectedLevelMusic: String?
    /// Per-minigame music for the selected level.
    private(set) var selectedGameMusic: GameMusicConfig
    /// Still background basename for the selected level's main game scene.
    private(set) var selectedLevelBackground: String?
    /// Per-minigame still backgrounds for the selected level.
    private(set) var selectedGameBackground: GameBackgroundConfig
    /// Pit puzzle knobs for the selected level.
    private(set) var selectedPitConfig: PitPuzzleConfig
    /// Gate puzzle knobs for the selected level.
    private(set) var selectedGateConfig: GatePuzzleConfig
    /// Destructible-wall puzzle knobs for the selected level.
    private(set) var selectedDestructibleWallConfig: DestructibleWallPuzzleConfig
    /// Shared letter-name prompt replay interval for combat / wall / related games.
    private(set) var selectedLetterSoundRepeatSeconds: Double
    let playerConfig: PlayerConfig
    let enemyConfig: EnemyConfig
    let itemsConfig: ItemsConfig
    let uiSpritesConfig: UISpritesConfig
    let playerStore: PlayerStateStore
    private(set) var saveService: GameSaveService
    private(set) var hasCompatibleSave: Bool
    private(set) var currentPlayerName: String?
    private(set) var playerState: PlayerGameState?
    let audioPreferences: AudioPreferences
    /// Session-scoped sprite animation cache (sheets sliced once per process).
    let spriteLibrary: SpriteLibrary
    /// Floor terrain definitions from `terrain.yaml`.
    let terrainCatalog: TerrainCatalog
    /// Session-scoped floor tile animation cache (all terrains sliced at game open).
    let floorSpriteLibrary: FloorSpriteLibrary
    /// Session-scoped still background cache (screen BGs at game open; engine BGs at level start).
    let backgroundLibrary: BackgroundLibrary

    init(
        seedConfig: WorldSeedConfig,
        selectedLevelName: String = LevelConfig.fallback.name,
        selectedLevelResourceName: String? = nil,
        selectedLevelArtifact: String = LevelConfig.fallbackArtifact,
        selectedLevelMusic: String? = LevelConfig.fallback.music,
        selectedGameMusic: GameMusicConfig = .fallback,
        selectedLevelBackground: String? = LevelConfig.fallback.background,
        selectedGameBackground: GameBackgroundConfig = .fallback,
        selectedPitConfig: PitPuzzleConfig = .fallback,
        selectedGateConfig: GatePuzzleConfig = .fallback,
        selectedDestructibleWallConfig: DestructibleWallPuzzleConfig = .fallback,
        selectedLetterSoundRepeatSeconds: Double = LevelConfig.fallback.letterSoundRepeatSeconds,
        playerConfig: PlayerConfig? = nil,
        enemyConfig: EnemyConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        uiSpritesConfig: UISpritesConfig? = nil,
        playerStore: PlayerStateStore,
        saveService: GameSaveService,
        hasCompatibleSave: Bool = false,
        currentPlayerName: String? = nil,
        playerState: PlayerGameState? = nil,
        audioPreferences: AudioPreferences? = nil,
        spriteLibrary: SpriteLibrary? = nil,
        terrainCatalog: TerrainCatalog? = nil,
        floorSpriteLibrary: FloorSpriteLibrary? = nil,
        backgroundLibrary: BackgroundLibrary? = nil
    ) {
        self.seedConfig = seedConfig
        self.selectedLevelName = selectedLevelName
        self.selectedLevelResourceName = selectedLevelResourceName
        self.selectedLevelArtifact = selectedLevelArtifact
        self.selectedLevelMusic = selectedLevelMusic
        self.selectedGameMusic = selectedGameMusic
        self.selectedLevelBackground = selectedLevelBackground
        self.selectedGameBackground = selectedGameBackground
        self.selectedPitConfig = selectedPitConfig
        self.selectedGateConfig = selectedGateConfig
        self.selectedDestructibleWallConfig = selectedDestructibleWallConfig
        self.selectedLetterSoundRepeatSeconds = selectedLetterSoundRepeatSeconds
        // Default-argument expressions are nonisolated; resolve MainActor defaults in-body.
        self.playerConfig = playerConfig ?? .fallback
        self.enemyConfig = enemyConfig ?? .fallback
        self.itemsConfig = itemsConfig ?? .fallback
        self.uiSpritesConfig = uiSpritesConfig ?? .fallback
        self.playerStore = playerStore
        self.saveService = saveService
        self.hasCompatibleSave = hasCompatibleSave
        self.currentPlayerName = currentPlayerName
        self.playerState = playerState
        self.audioPreferences = audioPreferences ?? .shared
        self.spriteLibrary = spriteLibrary ?? SpriteLibrary()
        self.terrainCatalog = terrainCatalog ?? TerrainCatalog(
            sprite: FloorSpriteConfig(
                root: "Sprites/Floor",
                sheet: "floor-spritesheet",
                atlasRoot: "Sprites/Floor",
                atlas: "atlas",
                chromaKey: "#FFFFFF",
                chromaKeyTolerance: 18,
                chromaKeyFeather: 48,
                chromaKeySmooth: 2
            ),
            terrains: [:]
        )
        self.floorSpriteLibrary = floorSpriteLibrary ?? FloorSpriteLibrary()
        self.backgroundLibrary = backgroundLibrary ?? BackgroundLibrary()
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
    func ensureItemSpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let entries = itemsConfig.items.compactMap { id, item -> (String, SpriteConfig)? in
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

    /// Ensures UI sprites (level-select planets, …) are loaded for this session.
    func ensureUISpritesLoaded(onProgress: ((Double) -> Void)? = nil) async {
        let entries = uiSpritesConfig.sprites.compactMap { id, entry -> (String, SpriteConfig)? in
            guard let sprite = entry.sprite else { return nil }
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

    /// Ensures engine backgrounds for the selected level are loaded into the session cache.
    func ensureEngineBackgroundsLoaded(onProgress: ((Double) -> Void)? = nil) async {
        var names: [String] = []
        if let selectedLevelBackground {
            names.append(selectedLevelBackground)
        }
        names.append(contentsOf: selectedGameBackground.backgroundNames)
        await backgroundLibrary.ensureLoaded(names: names, onProgress: onProgress)
    }

    nonisolated static func fallbackConfig() -> WorldSeedConfig {
        let level = LevelConfig.fallback
        return WorldSeedConfig(
            version: 1,
            seed: nil,
            world: WorldSeedConfig.WorldSize(
                width: level.width,
                height: level.height,
                stories: 1
            ),
            generation: level.generation,
            display: WorldSeedConfig.DisplayParams(tileWidth: 40, tileHeight: 40),
            enemies: level.enemies,
            pickups: level.pickups,
            extensions: nil
        )
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

        let seedConfig: WorldSeedConfig
        let selectedLevelName: String
        let selectedLevelArtifact: String
        let selectedLevelMusic: String?
        let selectedGameMusic: GameMusicConfig
        let selectedLevelBackground: String?
        let selectedGameBackground: GameBackgroundConfig
        let selectedPitConfig: PitPuzzleConfig
        let selectedGateConfig: GatePuzzleConfig
        let selectedDestructibleWallConfig: DestructibleWallPuzzleConfig
        let selectedLetterSoundRepeatSeconds: Double
        do {
            let loaded = try WorldLoader.loadConfigAndLevelFromBundle()
            try loaded.config.validate()
            seedConfig = loaded.config
            selectedLevelName = loaded.level.name
            selectedLevelArtifact = loaded.level.artifact
            selectedLevelMusic = loaded.level.music
            selectedGameMusic = loaded.level.gameMusic
            selectedLevelBackground = loaded.level.background
            selectedGameBackground = loaded.level.gameBackground
            selectedPitConfig = loaded.level.pit
            selectedGateConfig = loaded.level.gate
            selectedDestructibleWallConfig = loaded.level.destructibleWall
            selectedLetterSoundRepeatSeconds = loaded.level.letterSoundRepeatSeconds
        } catch {
            seedConfig = fallbackConfig()
            selectedLevelName = LevelConfig.fallback.name
            selectedLevelArtifact = LevelConfig.fallback.artifact
            selectedLevelMusic = LevelConfig.fallback.music
            selectedGameMusic = LevelConfig.fallback.gameMusic
            selectedLevelBackground = LevelConfig.fallback.background
            selectedGameBackground = LevelConfig.fallback.gameBackground
            selectedPitConfig = LevelConfig.fallback.pit
            selectedGateConfig = LevelConfig.fallback.gate
            selectedDestructibleWallConfig = LevelConfig.fallback.destructibleWall
            selectedLetterSoundRepeatSeconds = LevelConfig.fallback.letterSoundRepeatSeconds
        }
        await report(0.03)

        let soundSettings: SoundSettings
        do {
            let loaded = try SoundSettings.loadFromBundle()
            try loaded.validate()
            soundSettings = loaded
        } catch {
            soundSettings = .fallback
        }
        BackgroundMusicController.shared.configure(fadeSeconds: soundSettings.fadeSeconds)
        SoundEffectsController.shared.configure(commonFx: soundSettings.fx)
        AudioPreferences.shared.applyToControllers()
        await report(0.06)

        let playerConfig: PlayerConfig
        do {
            let loaded = try PlayerConfig.loadFromBundle()
            try loaded.validate()
            playerConfig = loaded
        } catch {
            playerConfig = .fallback
        }

        let enemyConfig: EnemyConfig
        do {
            let loaded = try EnemyConfig.loadFromBundle()
            try loaded.validate()
            enemyConfig = loaded
        } catch {
            enemyConfig = .fallback
        }

        let itemsConfig: ItemsConfig
        do {
            let loaded = try ItemsConfig.loadFromBundle()
            try loaded.validate()
            itemsConfig = loaded
        } catch {
            itemsConfig = .fallback
        }

        let uiSpritesConfig: UISpritesConfig
        do {
            let loaded = try UISpritesConfig.loadFromBundle()
            try loaded.validate()
            uiSpritesConfig = loaded
        } catch {
            uiSpritesConfig = .fallback
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

        let terrainCatalog: TerrainCatalog
        if let loaded = try? TerrainCatalog.loadFromBundle() {
            terrainCatalog = loaded
        } else {
            terrainCatalog = TerrainCatalog(
                sprite: FloorSpriteConfig(
                    root: "Sprites/Floor",
                    sheet: "floor-spritesheet",
                    atlasRoot: "Sprites/Floor",
                    atlas: "atlas",
                    chromaKey: "#FFFFFF",
                    chromaKeyTolerance: 18,
                    chromaKeyFeather: 48,
                    chromaKeySmooth: 2
                ),
                terrains: [:]
            )
        }
        await report(configEnd)

        let spriteLibrary = SpriteLibrary()
        let backgroundLibrary = BackgroundLibrary()
        // Level-select planet art: load at game open so the picker has sprites ready.
        let uiEntries = uiSpritesConfig.sprites.compactMap { id, entry -> (String, SpriteConfig)? in
            guard let sprite = entry.sprite else { return nil }
            return (id, sprite)
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

        // All screen backgrounds referenced by Screens/*.yaml.
        let screenBackgroundNames = BackgroundLibrary.screenBackgroundNames()
        let backgroundsEnd = screenBackgroundNames.isEmpty ? uiEnd : 0.32
        await backgroundLibrary.ensureLoaded(names: screenBackgroundNames) { local in
            onProgress?(LoadProgress.map(local, from: uiEnd, to: backgroundsEnd))
        }
        await report(backgroundsEnd)

        let floorSpriteLibrary = FloorSpriteLibrary()
        // Slice all floor terrains once at game open so every level can reuse them.
        await floorSpriteLibrary.ensureLoaded(catalog: terrainCatalog) { local in
            onProgress?(LoadProgress.map(local, from: backgroundsEnd, to: 1))
        }
        await report(1)

        return AppSession(
            seedConfig: seedConfig,
            selectedLevelName: selectedLevelName,
            selectedLevelArtifact: selectedLevelArtifact,
            selectedLevelMusic: selectedLevelMusic,
            selectedGameMusic: selectedGameMusic,
            selectedLevelBackground: selectedLevelBackground,
            selectedGameBackground: selectedGameBackground,
            selectedPitConfig: selectedPitConfig,
            selectedGateConfig: selectedGateConfig,
            selectedDestructibleWallConfig: selectedDestructibleWallConfig,
            selectedLetterSoundRepeatSeconds: selectedLetterSoundRepeatSeconds,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            itemsConfig: itemsConfig,
            uiSpritesConfig: uiSpritesConfig,
            playerStore: playerStore,
            saveService: saveService,
            hasCompatibleSave: false,
            spriteLibrary: spriteLibrary,
            terrainCatalog: terrainCatalog,
            floorSpriteLibrary: floorSpriteLibrary,
            backgroundLibrary: backgroundLibrary
        )
    }

    func selectLevel(resourceName: String) throws {
        let loaded = try WorldLoader.loadConfigAndLevelFromBundle(
            levelNamed: resourceName,
            levelSubdirectory: LevelCatalog.subdirectory
        )
        try loaded.config.validate()
        seedConfig = loaded.config
        selectedLevelName = loaded.level.name
        selectedLevelResourceName = resourceName
        selectedLevelArtifact = loaded.level.artifact
        selectedLevelMusic = loaded.level.music
        selectedGameMusic = loaded.level.gameMusic
        selectedLevelBackground = loaded.level.background
        selectedGameBackground = loaded.level.gameBackground
        selectedPitConfig = loaded.level.pit
        selectedGateConfig = loaded.level.gate
        selectedDestructibleWallConfig = loaded.level.destructibleWall
        selectedLetterSoundRepeatSeconds = loaded.level.letterSoundRepeatSeconds
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

    nonisolated static func isContinueEligible(savedWorld: GameWorld?, config: WorldSeedConfig) -> Bool {
        guard let savedWorld else { return false }
        return WorldLoader.isCompatibleSave(savedWorld, with: config)
    }

    func refreshContinueEligibility() async {
        guard currentPlayerName != nil else {
            hasCompatibleSave = false
            return
        }

        var config = seedConfig
        if let lastLevel = playerState?.lastLevelStarted {
            if let loaded = try? WorldLoader.loadConfigAndLevelFromBundle(
                levelNamed: lastLevel,
                levelSubdirectory: LevelCatalog.subdirectory
            ) {
                config = loaded.config
            }
        }

        hasCompatibleSave = await Self.probeCompatibleSave(
            saveService: saveService,
            config: config
        )
    }

    private static func probeCompatibleSave(
        saveService: GameSaveService,
        config: WorldSeedConfig
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
