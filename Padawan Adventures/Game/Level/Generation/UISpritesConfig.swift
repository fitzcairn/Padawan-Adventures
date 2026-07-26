import Foundation
import Yams

/// One UI sprite definition from screen YAML (keyed by sprite id).
nonisolated struct UISpriteDefinition: Codable, Equatable, Sendable {
    /// Animated / still sprite definition (`Resources/Sprites/...`).
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sprite, forKey: .sprite)
    }
}

/// Sprite definitions for UI chrome (level-select planets, …).
///
/// Loaded from `Resources/Config/Screens/level_select.yaml`. Top-level keys other
/// than sprite entries (e.g. `music:`) are ignored.
nonisolated struct UISpritesConfig: Codable, Equatable, Sendable {
    /// Sprite id → definition (`tython`, `tatooine`, …).
    var sprites: [String: UISpriteDefinition]

    init(sprites: [String: UISpriteDefinition] = [:]) {
        self.sprites = sprites
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decoded: [String: UISpriteDefinition] = [:]
        for key in container.allKeys {
            // Screen YAML also carries non-sprite fields (`music:`); skip those.
            guard let entry = try? container.decode(UISpriteDefinition.self, forKey: key),
                  entry.sprite != nil else {
                continue
            }
            decoded[key.stringValue] = entry
        }
        sprites = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (id, entry) in sprites {
            try container.encode(entry, forKey: DynamicCodingKey(stringValue: id))
        }
    }

    nonisolated static let fallback = UISpritesConfig(sprites: [:])

    func spriteConfig(for id: String) -> SpriteConfig? {
        sprites[id]?.sprite
    }

    func validate() throws {
        for (id, entry) in sprites {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UISpritesConfigError.invalid("sprite id must be non-empty")
            }
            if let sprite = entry.sprite {
                guard !sprite.root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw UISpritesConfigError.invalid("\(id).sprite.root must be non-empty")
                }
            }
        }
    }

    static func loadFromBundle(
        named name: String = "level_select",
        withExtension ext: String = "yaml",
        subdirectory: String? = ScreenConfig.subdirectory
    ) throws -> UISpritesConfig {
        let data = try resourceData(named: name, withExtension: ext, subdirectory: subdirectory)
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> UISpritesConfig {
        do {
            return try YAMLDecoder().decode(UISpritesConfig.self, from: data)
        } catch let error as UISpritesConfigError {
            throw error
        } catch {
            throw UISpritesConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> UISpritesConfig {
        try decode(from: Data(yaml.utf8))
    }

    private static func resourceData(
        named name: String,
        withExtension ext: String,
        subdirectory: String?
    ) throws -> Data {
        if let subdirectory,
           let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return try Data(contentsOf: url)
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw UISpritesConfigError.missingResource
        }
        return try Data(contentsOf: url)
    }
}

nonisolated enum UISpritesConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
