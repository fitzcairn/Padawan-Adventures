import Foundation

/// Shared bootstrap state loaded before the menu appears.
@MainActor
final class AppSession {
    private(set) var seedConfig: WorldSeedConfig
    private(set) var selectedLevelName: String
    private(set) var selectedLevelResourceName: String?
    let playerConfig: PlayerConfig
    let enemyConfig: EnemyConfig
    let playerStore: PlayerStateStore
    private(set) var saveService: GameSaveService
    private(set) var hasCompatibleSave: Bool
    private(set) var currentPlayerName: String?
    private(set) var playerState: PlayerGameState?

    init(
        seedConfig: WorldSeedConfig,
        selectedLevelName: String = LevelConfig.fallback.name,
        selectedLevelResourceName: String? = nil,
        playerConfig: PlayerConfig? = nil,
        enemyConfig: EnemyConfig? = nil,
        playerStore: PlayerStateStore,
        saveService: GameSaveService,
        hasCompatibleSave: Bool = false,
        currentPlayerName: String? = nil,
        playerState: PlayerGameState? = nil
    ) {
        self.seedConfig = seedConfig
        self.selectedLevelName = selectedLevelName
        self.selectedLevelResourceName = selectedLevelResourceName
        // Default-argument expressions are nonisolated; resolve MainActor defaults in-body.
        self.playerConfig = playerConfig ?? .fallback
        self.enemyConfig = enemyConfig ?? .fallback
        self.playerStore = playerStore
        self.saveService = saveService
        self.hasCompatibleSave = hasCompatibleSave
        self.currentPlayerName = currentPlayerName
        self.playerState = playerState
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
            enemies: WorldSeedConfig.EnemiesSpawnConfig(type: "grunt", spawnChancePerRoom: 0.8),
            pickups: level.pickups,
            extensions: nil
        )
    }

    /// Loads seed config, player store, and an unbound save service.
    static func loadResources() async -> AppSession {
        let seedConfig: WorldSeedConfig
        let selectedLevelName: String
        do {
            let loaded = try WorldLoader.loadConfigAndLevelFromBundle()
            try loaded.config.validate()
            seedConfig = loaded.config
            selectedLevelName = loaded.level.name
        } catch {
            seedConfig = fallbackConfig()
            selectedLevelName = LevelConfig.fallback.name
        }

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

        return AppSession(
            seedConfig: seedConfig,
            selectedLevelName: selectedLevelName,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            playerStore: playerStore,
            saveService: saveService,
            hasCompatibleSave: false
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
    }

    func bindPlayer(name: String) async throws {
        let trimmed = PlayerStateStore.normalizedName(name)
        let state = try await playerStore.loadState(for: trimmed)
        let playerSaveService = try await playerStore.makeSaveService(for: trimmed)

        currentPlayerName = trimmed
        playerState = state
        saveService = playerSaveService

        if let lastLevel = state.lastLevelStarted {
            try? selectLevel(resourceName: lastLevel)
        }

        await refreshContinueEligibility()
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

    func markLevelStarted(resourceName: String) async {
        playerState?.markLevelStarted(resourceName)
        selectedLevelResourceName = resourceName
        await persistPlayerState()
    }

    func markLevelCompleted(resourceName: String) async {
        playerState?.markLevelCompleted(resourceName)
        await persistPlayerState()
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
