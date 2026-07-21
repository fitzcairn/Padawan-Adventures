import Foundation
import Yams

/// Per-level map size and generation settings loaded from `level.yaml`.
nonisolated struct LevelConfig: Codable, Equatable, Sendable {
    var width: Int
    var height: Int
    var algorithm: String
    var roomCount: Int
    var corridorWidth: Int
    var room: WorldSeedConfig.RoomParams

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case algorithm
        case roomCount = "room_count"
        case corridorWidth = "corridor_width"
        case room
    }

    nonisolated static let fallback = LevelConfig(
        width: 100,
        height: 100,
        algorithm: "rooms_doors",
        roomCount: 100,
        corridorWidth: 2,
        room: .init(
            minRoomSize: 4,
            maxRoomSize: 12,
            pitChance: 0.2,
            pitMeanSize: 2,
            pitMaxSize: 5,
            wallDestructibleChance: 0.8,
            gateChance: 0.5
        )
    )

    nonisolated init(
        width: Int,
        height: Int,
        algorithm: String,
        roomCount: Int,
        corridorWidth: Int,
        room: WorldSeedConfig.RoomParams
    ) {
        self.width = width
        self.height = height
        self.algorithm = algorithm
        self.roomCount = roomCount
        self.corridorWidth = corridorWidth
        self.room = room
    }

    var generation: WorldSeedConfig.GenerationParams {
        .init(
            algorithm: algorithm,
            roomCount: roomCount,
            corridorWidth: corridorWidth,
            room: room
        )
    }

    static func loadFromBundle(
        named name: String = "level",
        withExtension ext: String = "yaml"
    ) throws -> LevelConfig {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> LevelConfig {
        do {
            return try YAMLDecoder().decode(LevelConfig.self, from: data)
        } catch {
            throw WorldSeedError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> LevelConfig {
        try decode(from: Data(yaml.utf8))
    }
}
