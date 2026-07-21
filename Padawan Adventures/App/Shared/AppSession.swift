import Foundation

/// Shared bootstrap state loaded before the menu appears.
@MainActor
final class AppSession {
    let seedConfig: WorldSeedConfig
    let playerConfig: PlayerConfig
    let enemyConfig: EnemyConfig
    let saveService: GameSaveService
    private(set) var hasCompatibleSave: Bool

    init(
        seedConfig: WorldSeedConfig,
        playerConfig: PlayerConfig? = nil,
        enemyConfig: EnemyConfig? = nil,
        saveService: GameSaveService,
        hasCompatibleSave: Bool
    ) {
        self.seedConfig = seedConfig
        // Default-argument expressions are nonisolated; resolve MainActor defaults in-body.
        self.playerConfig = playerConfig ?? .fallback
        self.enemyConfig = enemyConfig ?? .fallback
        self.saveService = saveService
        self.hasCompatibleSave = hasCompatibleSave
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
            extensions: nil
        )
    }

    /// Loads seed config, save service, and continue eligibility.
    static func loadResources() async -> AppSession {
        let seedConfig: WorldSeedConfig
        do {
            let loaded = try WorldLoader.loadConfigFromBundle()
            try loaded.validate()
            seedConfig = loaded
        } catch {
            seedConfig = fallbackConfig()
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

        let saveService: GameSaveService
        if let primary = try? GameSaveService() {
            saveService = primary
        } else {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("PadawanAdventures", isDirectory: true)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            saveService = try! GameSaveService(directoryURL: temp)
        }

        let hasCompatibleSave = await Self.probeCompatibleSave(
            saveService: saveService,
            config: seedConfig
        )

        return AppSession(
            seedConfig: seedConfig,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            saveService: saveService,
            hasCompatibleSave: hasCompatibleSave
        )
    }

    nonisolated static func isContinueEligible(savedWorld: GameWorld?, config: WorldSeedConfig) -> Bool {
        guard let savedWorld else { return false }
        return WorldLoader.isCompatibleSave(savedWorld, with: config)
    }

    func refreshContinueEligibility() async {
        hasCompatibleSave = await Self.probeCompatibleSave(
            saveService: saveService,
            config: seedConfig
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

enum GameLaunchMode: Equatable, Sendable {
    case continueSave
    case newGame
}
