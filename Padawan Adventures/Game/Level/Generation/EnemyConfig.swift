import Foundation
import UIKit
import Yams

nonisolated struct EnemyConfig: Codable, Equatable, Sendable {
    /// Max seconds a combat slash stays active after the initial tap.
    var slashMaxSeconds: Double
    /// Max slash path length as a fraction of combat scene width (e.g. 0.05 = 5%).
    var slashMaxScreenWidthFraction: Double
    var enemies: [String: EnemyTypeConfig]
    /// Shared sprite definitions referenced by `EnemyTypeConfig.sprite`.
    var sprites: [String: SpriteConfig]
    /// Combat projectile sheets referenced by `EnemyTypeConfig.projectile`.
    var projectiles: [String: SpriteConfig]

    enum CodingKeys: String, CodingKey {
        case slashMaxSeconds = "slash_max_seconds"
        case slashMaxScreenWidthFraction = "slash_max_screen_width_fraction"
        case enemies
        case sprites
        case projectiles
    }

    nonisolated static let fallbackSlashMaxSeconds: Double = 0.5
    nonisolated static let fallbackSlashMaxScreenWidthFraction: Double = 0.20

    nonisolated static let fallback = EnemyConfig(
        slashMaxSeconds: fallbackSlashMaxSeconds,
        slashMaxScreenWidthFraction: fallbackSlashMaxScreenWidthFraction,
        enemies: [
            "spider": EnemyTypeConfig(
                letter: "E",
                color: "#FF0000",
                tilesPerSecond: 1.0,
                forgetSeconds: 3.0,
                shotPacingSeconds: 10,
                shotTravelSeconds: 3.2,
                starsToWin: 10,
                shotTypes: EnemyTypeConfig.fallbackShotTypes,
                fx: .empty
            ),
        ]
    )

    init(
        slashMaxSeconds: Double = fallbackSlashMaxSeconds,
        slashMaxScreenWidthFraction: Double = fallbackSlashMaxScreenWidthFraction,
        enemies: [String: EnemyTypeConfig],
        sprites: [String: SpriteConfig] = [:],
        projectiles: [String: SpriteConfig] = [:]
    ) {
        self.slashMaxSeconds = slashMaxSeconds
        self.slashMaxScreenWidthFraction = slashMaxScreenWidthFraction
        self.enemies = enemies
        self.sprites = sprites
        self.projectiles = projectiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slashMaxSeconds = try container.decodeIfPresent(Double.self, forKey: .slashMaxSeconds)
            ?? Self.fallbackSlashMaxSeconds
        slashMaxScreenWidthFraction = try container.decodeIfPresent(
            Double.self,
            forKey: .slashMaxScreenWidthFraction
        ) ?? Self.fallbackSlashMaxScreenWidthFraction
        enemies = try container.decode([String: EnemyTypeConfig].self, forKey: .enemies)
        sprites = try container.decodeIfPresent([String: SpriteConfig].self, forKey: .sprites) ?? [:]
        projectiles = try container.decodeIfPresent([String: SpriteConfig].self, forKey: .projectiles) ?? [:]
    }

    func validate() throws {
        guard slashMaxSeconds > 0 else {
            throw EnemyConfigError.invalid("slash_max_seconds must be > 0")
        }
        guard slashMaxScreenWidthFraction > 0, slashMaxScreenWidthFraction <= 1 else {
            throw EnemyConfigError.invalid(
                "slash_max_screen_width_fraction must be in (0, 1]"
            )
        }
        guard !enemies.isEmpty else {
            throw EnemyConfigError.invalid("enemies must not be empty")
        }
        for (id, type) in enemies {
            try type.validate(typeID: id)
            if let spriteID = type.sprite, sprites[spriteID] == nil {
                throw EnemyConfigError.invalid("\(id).sprite references unknown sprite '\(spriteID)'")
            }
            if let projectileID = type.projectile, projectiles[projectileID] == nil {
                throw EnemyConfigError.invalid(
                    "\(id).projectile references unknown projectile '\(projectileID)'"
                )
            }
        }
    }

    func type(named id: String) -> EnemyTypeConfig? {
        enemies[id]
    }

    /// Resolves an enemy type's shared sprite entry from the `sprites:` map.
    func spriteConfig(for typeID: String) -> (id: String, config: SpriteConfig)? {
        guard let spriteID = enemies[typeID]?.sprite,
              let config = sprites[spriteID] else { return nil }
        return (spriteID, config)
    }

    /// Resolves an enemy type's projectile sprite from the `projectiles:` map.
    /// The `projectile_` prefix namespaces the SpriteLibrary id away from body sprites.
    func projectileSpriteConfig(for typeID: String) -> (id: String, config: SpriteConfig)? {
        guard let projectileID = enemies[typeID]?.projectile,
              let config = projectiles[projectileID] else { return nil }
        return ("projectile_\(projectileID)", config)
    }

    static func loadFromBundle(
        named name: String = "enemies",
        withExtension ext: String = "yaml"
    ) throws -> EnemyConfig {
        let data = try ConfigStore.data(at: .catalog(name))
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> EnemyConfig {
        do {
            let tree = try ConfigStore.rawTree(
                from: data,
                parentDataNamed: nil,
                fileLabel: "enemies.yaml"
            )
            let yaml = try Yams.dump(object: tree)
            let config = try YAMLDecoder().decode(EnemyConfigDTO.self, from: yaml).asEnemyConfig()
            try config.validate()
            return config
        } catch let error as EnemyConfigError {
            throw error
        } catch is ConfigError {
            throw EnemyConfigError.decodeFailed
        } catch {
            throw EnemyConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> EnemyConfig {
        try decode(from: Data(yaml.utf8))
    }
}

/// Intermediate decode shape that still accepts injected `shot_types` maps.
private nonisolated struct EnemyConfigDTO: Decodable, Sendable {
    var slashMaxSeconds: Double?
    var slashMaxScreenWidthFraction: Double?
    var enemies: [String: EnemyTypeConfigDTO]
    var sprites: [String: SpriteConfig]?
    var projectiles: [String: SpriteConfig]?

    enum CodingKeys: String, CodingKey {
        case slashMaxSeconds = "slash_max_seconds"
        case slashMaxScreenWidthFraction = "slash_max_screen_width_fraction"
        case enemies
        case sprites
        case projectiles
    }

    nonisolated func asEnemyConfig() -> EnemyConfig {
        EnemyConfig(
            slashMaxSeconds: slashMaxSeconds ?? EnemyConfig.fallbackSlashMaxSeconds,
            slashMaxScreenWidthFraction: slashMaxScreenWidthFraction
                ?? EnemyConfig.fallbackSlashMaxScreenWidthFraction,
            enemies: enemies.mapValues { $0.asEnemyTypeConfig() },
            sprites: sprites ?? [:],
            projectiles: projectiles ?? [:]
        )
    }
}

private nonisolated struct EnemyTypeConfigDTO: Decodable, Sendable {
    var letter: String
    var color: String
    var tilesPerSecond: Double
    var forgetSeconds: Double
    var shotPacingSeconds: Double?
    var shotTravelSeconds: Double?
    var starsToWin: Int?
    var shotTypes: [String: EnemyShotTypeConfig]?
    var fx: SoundEffectTable?
    var sprite: String?
    var projectile: String?

    enum CodingKeys: String, CodingKey {
        case letter
        case color
        case tilesPerSecond = "tiles_per_second"
        case forgetSeconds = "forget_seconds"
        case shotPacingSeconds = "shot_pacing_seconds"
        case shotTravelSeconds = "shot_travel_seconds"
        case starsToWin = "stars_to_win"
        case shotTypes = "shot_types"
        case fx
        case sprite
        case projectile
    }

    nonisolated func asEnemyTypeConfig() -> EnemyTypeConfig {
        EnemyTypeConfig(
            letter: letter,
            color: color,
            tilesPerSecond: tilesPerSecond,
            forgetSeconds: forgetSeconds,
            shotPacingSeconds: shotPacingSeconds ?? 10,
            shotTravelSeconds: shotTravelSeconds ?? 3.2,
            starsToWin: starsToWin ?? 10,
            shotTypes: shotTypes ?? EnemyTypeConfig.fallbackShotTypes,
            fx: fx ?? .empty,
            sprite: sprite,
            projectile: projectile
        )
    }
}

nonisolated enum EnemyConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
