import Foundation
import Yams

nonisolated enum WorldLoader {
    /// True when a saved world matches the configured map dimensions.
    nonisolated static func isCompatibleSave(_ world: GameWorld, with config: WorldSeedConfig) -> Bool {
        world.width == config.world.width
            && world.height == config.world.height
            && world.storyCount == config.world.stories
    }

    static func load(
        from url: URL,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback
    ) throws -> GameWorld {
        let data = try Data(contentsOf: url)
        let config = try decodeConfig(from: data)
        return try ProceduralGenerator().generate(
            from: config,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig
        )
    }

    static func loadConfigFromBundle(
        named name: String = "world",
        withExtension ext: String = "yaml",
        levelNamed levelName: String = "base_level",
        levelSubdirectory: String? = nil
    ) throws -> WorldSeedConfig {
        try loadConfigAndLevelFromBundle(
            named: name,
            withExtension: ext,
            levelNamed: levelName,
            levelSubdirectory: levelSubdirectory
        ).config
    }

    static func loadConfigAndLevelFromBundle(
        named name: String = "world",
        withExtension ext: String = "yaml",
        levelNamed levelName: String = "base_level",
        levelSubdirectory: String? = nil
    ) throws -> (config: WorldSeedConfig, level: LevelConfig) {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        let data = try Data(contentsOf: url)
        var config = try decodeConfig(from: data)
        let level = try LevelConfig.loadFromBundle(
            named: levelName,
            withExtension: ext,
            subdirectory: levelSubdirectory
        )
        config.world.width = level.width
        config.world.height = level.height
        config.generation = level.generation
        config.pickups = level.pickups
        return (config, level)
    }

    static func loadFromBundle(
        named name: String = "world",
        withExtension ext: String = "yaml",
        levelNamed levelName: String = "base_level",
        levelSubdirectory: String? = nil,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback
    ) throws -> GameWorld {
        let config = try loadConfigFromBundle(
            named: name,
            withExtension: ext,
            levelNamed: levelName,
            levelSubdirectory: levelSubdirectory
        )
        return try ProceduralGenerator().generate(
            from: config,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig
        )
    }

    static func decodeConfig(from data: Data) throws -> WorldSeedConfig {
        let decoder = YAMLDecoder()
        do {
            return try decoder.decode(WorldSeedConfig.self, from: data)
        } catch {
            throw WorldSeedError.decodeFailed
        }
    }

    static func decodeConfig(from yaml: String) throws -> WorldSeedConfig {
        try decodeConfig(from: Data(yaml.utf8))
    }
}
