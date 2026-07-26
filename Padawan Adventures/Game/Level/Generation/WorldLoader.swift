import Foundation
import Yams

nonisolated enum WorldLoader {
    /// True when a saved world matches the configured map dimensions.
    nonisolated static func isCompatibleSave(
        _ world: GameWorld,
        with config: WorldGenerationConfig
    ) -> Bool {
        world.width == config.world.width
            && world.height == config.world.height
            && world.storyCount == config.world.stories
    }

    nonisolated static func isCompatibleSave(
        _ world: GameWorld,
        app: AppConfig,
        level: LevelConfig
    ) -> Bool {
        isCompatibleSave(world, with: .compose(app: app, level: level))
    }

    static func load(
        from url: URL,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback,
        terrainPlacement: TerrainPlacementTable? = nil
    ) throws -> GameWorld {
        let data = try Data(contentsOf: url)
        let app = try decodeConfig(from: data)
        let level = LevelConfig.fallback
        let placement = try terrainPlacement ?? Self.bundleTerrainPlacement()
        return try ProceduralGenerator().generate(
            from: app,
            level: level,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            terrainPlacement: placement
        )
    }

    static func loadConfigFromBundle(
        named name: String = "app",
        withExtension ext: String = "yaml",
        levelNamed levelName: String = "_defaults",
        levelSubdirectory: String? = LevelCatalog.subdirectory
    ) throws -> AppConfig {
        try loadConfigAndLevelFromBundle(
            named: name,
            withExtension: ext,
            levelNamed: levelName,
            levelSubdirectory: levelSubdirectory
        ).config
    }

    static func loadConfigAndLevelFromBundle(
        named name: String = "app",
        withExtension ext: String = "yaml",
        levelNamed levelName: String = "_defaults",
        levelSubdirectory: String? = LevelCatalog.subdirectory
    ) throws -> (config: AppConfig, level: LevelConfig) {
        let data = try ConfigStore.data(
            at: ConfigPath(basename: name, subdirectory: nil)
        )
        let config = try decodeConfig(from: data)
        let level = try LevelConfig.loadFromBundle(
            named: levelName,
            withExtension: ext,
            subdirectory: levelSubdirectory
        )
        return (config, level)
    }

    static func loadFromBundle(
        named name: String = "app",
        withExtension ext: String = "yaml",
        levelNamed levelName: String = "_defaults",
        levelSubdirectory: String? = LevelCatalog.subdirectory,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback,
        terrainPlacement: TerrainPlacementTable? = nil
    ) throws -> GameWorld {
        let loaded = try loadConfigAndLevelFromBundle(
            named: name,
            withExtension: ext,
            levelNamed: levelName,
            levelSubdirectory: levelSubdirectory
        )
        let placement = try terrainPlacement ?? Self.bundleTerrainPlacement()
        return try ProceduralGenerator().generate(
            from: loaded.config,
            level: loaded.level,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            terrainPlacement: placement
        )
    }

    /// Placement accents/specials from the bundled `terrain.yaml`.
    private static func bundleTerrainPlacement() throws -> TerrainPlacementTable {
        try TerrainCatalog.loadFromBundle().placementTable
    }

    static func decodeConfig(from data: Data) throws -> AppConfig {
        let decoder = YAMLDecoder()
        do {
            return try decoder.decode(AppConfig.self, from: data)
        } catch let error as WorldSeedError {
            throw error
        } catch {
            throw WorldSeedError.decodeFailed(String(describing: error))
        }
    }

    static func decodeConfig(from yaml: String) throws -> AppConfig {
        try decodeConfig(from: Data(yaml.utf8))
    }
}
