import Foundation
import Yams

enum WorldLoader {
    /// True when a saved world matches the configured map dimensions.
    static func isCompatibleSave(_ world: GameWorld, with config: WorldSeedConfig) -> Bool {
        world.width == config.world.width
            && world.height == config.world.height
            && world.storyCount == config.world.stories
    }

    static func load(from url: URL) throws -> GameWorld {
        let data = try Data(contentsOf: url)
        let config = try decodeConfig(from: data)
        return try ProceduralGenerator().generate(from: config)
    }

    static func loadConfigFromBundle(
        named name: String = "world_seed",
        withExtension ext: String = "yaml"
    ) throws -> WorldSeedConfig {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try decodeConfig(from: data)
    }

    static func loadFromBundle(named name: String = "world_seed", withExtension ext: String = "yaml") throws -> GameWorld {
        let config = try loadConfigFromBundle(named: name, withExtension: ext)
        return try ProceduralGenerator().generate(from: config)
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
