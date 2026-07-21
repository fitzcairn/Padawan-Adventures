import Foundation
import Yams

/// Procedural level generation settings loaded from `level.yaml`.
nonisolated enum LevelConfig {
    typealias Params = WorldSeedConfig.GenerationParams

    nonisolated static let fallback = Params(
        algorithm: "rooms_doors",
        roomCount: 100,
        corridorWidth: 2,
        room: .init(
            minRoomSize: 4,
            maxRoomSize: 12,
            pitChance: 0.2,
            wallDestructibleChance: 0.8,
            doorCount: 4
        )
    )

    static func loadFromBundle(
        named name: String = "level",
        withExtension ext: String = "yaml"
    ) throws -> Params {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> Params {
        do {
            return try YAMLDecoder().decode(Params.self, from: data)
        } catch {
            throw WorldSeedError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> Params {
        try decode(from: Data(yaml.utf8))
    }
}
