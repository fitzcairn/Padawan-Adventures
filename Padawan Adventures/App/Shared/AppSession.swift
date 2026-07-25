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
    let playerStore: PlayerStateStore
    private(set) var saveService: GameSaveService
    private(set) var hasCompatibleSave: Bool
    private(set) var currentPlayerName: String?
    private(set) var playerState: PlayerGameState?
    let audioPreferences: AudioPreferences
    /// Session-scoped sprite animation cache (sheets sliced once per process).
    let spriteLibrary: SpriteLibrary

    init(
        seedConfig: WorldSeedConfig,
        selectedLevelName: String = LevelConfig.fallback.name,
        selectedLevelResourceName: String? = nil,
        selectedLevelArtifact: String = LevelConfig.fallbackArtifact,
        selectedLevelMusic: String? = LevelConfig.fallback.music,
        selectedGameMusic: GameMusicConfig = .fallback,
        selectedPitConfig: PitPuzzleConfig = .fallback,
        selectedGateConfig: GatePuzzleConfig = .fallback,
        selectedDestructibleWallConfig: DestructibleWallPuzzleConfig = .fallback,
        selectedLetterSoundRepeatSeconds: Double = LevelConfig.fallback.letterSoundRepeatSeconds,
        playerConfig: PlayerConfig? = nil,
        enemyConfig: EnemyConfig? = nil,
        itemsConfig: ItemsConfig? = nil,
        playerStore: PlayerStateStore,
        saveService: GameSaveService,
        hasCompatibleSave: Bool = false,
        currentPlayerName: String? = nil,
        playerState: PlayerGameState? = nil,
        audioPreferences: AudioPreferences? = nil,
        spriteLibrary: SpriteLibrary? = nil
    ) {
        self.seedConfig = seedConfig
        self.selectedLevelName = selectedLevelName
        self.selectedLevelResourceName = selectedLevelResourceName
        self.selectedLevelArtifact = selectedLevelArtifact
        self.selectedLevelMusic = selectedLevelMusic
        self.selectedGameMusic = selectedGameMusic
        self.selectedPitConfig = selectedPitConfig
        self.selectedGateConfig = selectedGateConfig
        self.selectedDestructibleWallConfig = selectedDestructibleWallConfig
        self.selectedLetterSoundRepeatSeconds = selectedLetterSoundRepeatSeconds
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
    }

    /// Ensures player sprite animations are loaded for this session.
    func ensurePlayerSpritesLoaded() {
        guard let sprite = playerConfig.sprite else { return }
        spriteLibrary.ensureLoaded(sprite, id: "player")
    }

    /// Ensures item pickup sprite animations are loaded for this session.
    func ensureItemSpritesLoaded() {
        for (id, item) in itemsConfig.items {
            guard let sprite = item.sprite else { continue }
            spriteLibrary.ensureLoaded(sprite, id: id)
        }
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
    static func loadResources() async -> AppSession {
        let seedConfig: WorldSeedConfig
        let selectedLevelName: String
        let selectedLevelArtifact: String
        let selectedLevelMusic: String?
        let selectedGameMusic: GameMusicConfig
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
            selectedPitConfig = LevelConfig.fallback.pit
            selectedGateConfig = LevelConfig.fallback.gate
            selectedDestructibleWallConfig = LevelConfig.fallback.destructibleWall
            selectedLetterSoundRepeatSeconds = LevelConfig.fallback.letterSoundRepeatSeconds
        }

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
            selectedLevelArtifact: selectedLevelArtifact,
            selectedLevelMusic: selectedLevelMusic,
            selectedGameMusic: selectedGameMusic,
            selectedPitConfig: selectedPitConfig,
            selectedGateConfig: selectedGateConfig,
            selectedDestructibleWallConfig: selectedDestructibleWallConfig,
            selectedLetterSoundRepeatSeconds: selectedLetterSoundRepeatSeconds,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            itemsConfig: itemsConfig,
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
        selectedLevelArtifact = loaded.level.artifact
        selectedLevelMusic = loaded.level.music
        selectedGameMusic = loaded.level.gameMusic
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
