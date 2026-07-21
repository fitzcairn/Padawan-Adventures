import Foundation
import Yams

enum WorldLoader {
    static func load(from url: URL) throws -> GameWorld {
        let data = try Data(contentsOf: url)
        let config = try decodeConfig(from: data)
        return try ProceduralGenerator().generate(from: config)
    }

    static func loadFromBundle(named name: String = "world_seed", withExtension ext: String = "yaml") throws -> GameWorld {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        return try load(from: url)
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
