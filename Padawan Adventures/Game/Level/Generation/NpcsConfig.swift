import Foundation
import Yams

/// NPC sprite sheets and world FX from `Catalogs/npcs.yaml`.
nonisolated struct NpcsConfig: Codable, Equatable, Sendable {
    var sprites: [String: SpriteConfig]
    var fx: [String: SoundEffectTable]

    enum CodingKeys: String, CodingKey {
        case sprites
        case fx
    }

    nonisolated static let fallback = NpcsConfig()

    init(
        sprites: [String: SpriteConfig] = [:],
        fx: [String: SoundEffectTable] = [:]
    ) {
        self.sprites = sprites
        self.fx = fx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sprites = try container.decodeIfPresent([String: SpriteConfig].self, forKey: .sprites) ?? [:]
        fx = try container.decodeIfPresent([String: SoundEffectTable].self, forKey: .fx) ?? [:]
    }

    func spriteConfig(id: String) -> SpriteConfig? {
        sprites[id]
    }

    func fx(for id: String) -> SoundEffectTable {
        fx[id] ?? .empty
    }

    func validate() throws {
        for (id, sprite) in sprites {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NpcsConfigError.invalid("npc sprite id must be non-empty")
            }
            guard !sprite.root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NpcsConfigError.invalid("\(id).root must be non-empty")
            }
        }
    }

    static func loadFromBundle(
        named name: String = "npcs",
        withExtension ext: String = "yaml"
    ) throws -> NpcsConfig {
        let data = try ConfigStore.data(at: .catalog(name))
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> NpcsConfig {
        do {
            let config = try YAMLDecoder().decode(NpcsConfig.self, from: data)
            try config.validate()
            return config
        } catch let error as NpcsConfigError {
            throw error
        } catch {
            throw NpcsConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> NpcsConfig {
        try decode(from: Data(yaml.utf8))
    }
}

nonisolated enum NpcsConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
