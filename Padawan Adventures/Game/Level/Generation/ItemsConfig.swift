import Foundation
import UIKit
import Yams

/// One item definition from `items.yaml` (keyed by pickup id).
nonisolated struct ItemDefinition: Codable, Equatable, Sendable {
    /// Optional animated sprite definition (`Resources/Sprites/...`).
    var sprite: SpriteConfig?
    /// Optional particle halo drawn behind the sprite.
    var highlight: HighlightConfig?

    enum CodingKeys: String, CodingKey {
        case sprite
        case highlight
    }

    init(sprite: SpriteConfig? = nil, highlight: HighlightConfig? = nil) {
        self.sprite = sprite
        self.highlight = highlight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sprite = try container.decodeIfPresent(SpriteConfig.self, forKey: .sprite)
        highlight = try container.decodeIfPresent(HighlightConfig.self, forKey: .highlight)
    }
}

/// Sprite (and future) definitions for pickup item types.
nonisolated struct ItemsConfig: Codable, Equatable, Sendable {
    /// Pickup id → item definition (`energy`, `health`, …). The YAML `merchant:` map is
    /// not a pickup and is never stored here.
    var items: [String: ItemDefinition]
    /// Shop wares keyed by ware id (`merchant-ware-bridge`, …).
    var merchant: [String: MerchantItemDefinition]

    init(
        items: [String: ItemDefinition] = [:],
        merchant: [String: MerchantItemDefinition] = [:]
    ) {
        self.items = items
        self.merchant = merchant
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ConfigKey.self)
        var items: [String: ItemDefinition] = [:]
        var merchant: [String: MerchantItemDefinition] = [:]
        for key in container.allKeys {
            if key.stringValue == "merchant" {
                merchant = try container.decode([String: MerchantItemDefinition].self, forKey: key)
            } else {
                items[key.stringValue] = try container.decode(ItemDefinition.self, forKey: key)
            }
        }
        self.items = items
        self.merchant = merchant
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ConfigKey.self)
        for (id, item) in items {
            guard let key = ConfigKey(stringValue: id) else { continue }
            try container.encode(item, forKey: key)
        }
        if !merchant.isEmpty, let key = ConfigKey(stringValue: "merchant") {
            try container.encode(merchant, forKey: key)
        }
    }

    nonisolated static let fallback = ItemsConfig(items: [:], merchant: [:])

    /// Sprite config for a pickup kind when defined in `items.yaml`.
    func spriteConfig(for kind: PickupKind) -> SpriteConfig? {
        items[kind.rawValue]?.sprite
    }

    /// Sprite config for an arbitrary item id (e.g. a per-level treasure part).
    func spriteConfig(id: String) -> SpriteConfig? {
        items[id]?.sprite
    }

    /// Highlight config for an arbitrary item id, when the item opts in.
    func highlight(id: String) -> HighlightConfig? {
        items[id]?.highlight
    }

    func merchantItem(_ id: String) -> MerchantItemDefinition? {
        merchant[id]
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
            if let highlight = item.highlight {
                guard UIColor(hex: highlight.color) != nil else {
                    throw ItemsConfigError.invalid(
                        "\(id).highlight.color must be a hex color like #RRGGBB"
                    )
                }
                guard highlight.birthRate > 0 else {
                    throw ItemsConfigError.invalid(
                        "\(id).highlight.birth_rate_per_second must be greater than 0"
                    )
                }
                guard highlight.lifetime > 0 else {
                    throw ItemsConfigError.invalid(
                        "\(id).highlight.lifetime_seconds must be greater than 0"
                    )
                }
            }
        }

        guard items["merchant"] == nil else {
            throw ItemsConfigError.invalid("merchant must not be decoded as a pickup item")
        }

        for (id, ware) in merchant {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ItemsConfigError.invalid("merchant ware id must be non-empty")
            }
            guard ware.minLevel >= 1 else {
                throw ItemsConfigError.invalid("merchant.\(id).min_level must be >= 1")
            }
            guard ware.price > 0 else {
                throw ItemsConfigError.invalid("merchant.\(id).price must be greater than 0")
            }
            guard ware.limit >= 0 else {
                throw ItemsConfigError.invalid("merchant.\(id).limit must be >= 0")
            }
            guard !ware.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ItemsConfigError.invalid("merchant.\(id).description must be non-empty")
            }
            guard !ware.sprite.root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ItemsConfigError.invalid("merchant.\(id).sprite.root must be non-empty")
            }
        }
    }

    static func loadFromBundle(
        named name: String = "items",
        withExtension ext: String = "yaml"
    ) throws -> ItemsConfig {
        let data = try ConfigStore.data(at: .catalog(name))
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

    private struct ConfigKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}

nonisolated enum ItemsConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
