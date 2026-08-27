import Foundation

/// Marker protocol for types that participate in world save/restore.
/// Conforming types must remain `Codable` as the world model grows.
protocol WorldPersistable: Codable, Sendable {}

struct GameSaveFile: WorldPersistable {
    /// Persisted mid-run format. Bump when older app builds must not resume this world.
    nonisolated static let currentVersion = 2

    var version: Int
    var world: GameWorld

    nonisolated init(version: Int = GameSaveFile.currentVersion, world: GameWorld) {
        self.version = version
        self.world = world
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case world
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        world = try container.decode(GameWorld.self, forKey: .world)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(world, forKey: .world)
    }
}
