import Foundation
import Yams

/// One item definition from `items.yaml` (keyed by pickup id).
nonisolated struct ItemDefinition: Codable, Equatable, Sendable {
    /// Optional animated sprite definition (`Resources/Sprites/...`).
    var sprite: SpriteConfig?

    enum CodingKeys: String, CodingKey {
        case sprite
    }

    init(sprite: SpriteConfig? = nil) {
        self.sprite = sprite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sprite = try container.decodeIfPresent(SpriteConfig.self, forKey: .sprite)
    }
}

/// Sprite (and future) definitions for pickup item types.
nonisolated struct ItemsConfig: Codable, Equatable, Sendable {
    /// Pickup id → item definition (`energy`, `health`, …).
    var items: [String: ItemDefinition]

    init(items: [String: ItemDefinition] = [:]) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        items = try container.decode([String: ItemDefinition].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }

    nonisolated static let fallback = ItemsConfig(items: [:])

    /// Sprite config for a pickup kind when defined in `items.yaml`.
    func spriteConfig(for kind: PickupKind) -> SpriteConfig? {
        items[kind.rawValue]?.sprite
    }

    /// Sprite config for an arbitrary item id (e.g. a per-level treasure part).
    func spriteConfig(id: String) -> SpriteConfig? {
        items[id]?.sprite
    }

    func validate() throws {
        for (id, item) in items {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ItemsConfigError.invalid("item id must be non-empty")
            }
            if let sprite = item.sprite {
                guard !sprite.root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ItemsConfigError.invalid("\(id).sprite.root must be non-empty")
                }
            }
        }
    }

    static func loadFromBundle(
        named name: String = "items",
        withExtension ext: String = "yaml"
    ) throws -> ItemsConfig {
        let data = try ConfigStore.data(
            at: ConfigPath(basename: name, subdirectory: "Catalogs")
        )
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> ItemsConfig {
        do {
            return try YAMLDecoder().decode(ItemsConfig.self, from: data)
        } catch let error as ItemsConfigError {
            throw error
        } catch {
            throw ItemsConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> ItemsConfig {
        try decode(from: Data(yaml.utf8))
    }
}

nonisolated enum ItemsConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
