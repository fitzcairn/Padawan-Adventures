import Foundation
import Yams

nonisolated struct PlayerConfig: Codable, Equatable, Sendable {
    var letter: String
    var startingHealth: Int
    var startingEnergy: Int
    var spawn: SpawnCoord?
    /// Event key → sound track basename (`Resources/Audio/FX/`).
    var fx: SoundEffectTable
    /// Optional animated sprite definition (`Resources/Sprites/...`).
    var sprite: SpriteConfig?
    /// Optional combat-arena swing sprite (`Resources/Sprites/Combat/...`).
    var combatSprite: SpriteConfig?

    struct SpawnCoord: Codable, Equatable, Sendable {
        var x: Int
        var y: Int
        var story: Int
    }

    enum CodingKeys: String, CodingKey {
        case letter
        case startingHealth = "starting_health"
        case startingEnergy = "starting_energy"
        case spawn
        case fx
        case sprite
        case combatSprite = "combat_sprite"
    }

    init(
        letter: String,
        startingHealth: Int = 0,
        startingEnergy: Int = 0,
        spawn: SpawnCoord? = nil,
        fx: SoundEffectTable = .empty,
        sprite: SpriteConfig? = nil,
        combatSprite: SpriteConfig? = nil
    ) {
        self.letter = letter
        self.startingHealth = startingHealth
        self.startingEnergy = startingEnergy
        self.spawn = spawn
        self.fx = fx
        self.sprite = sprite
        self.combatSprite = combatSprite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        letter = try container.decode(String.self, forKey: .letter)
        startingHealth = try container.decode(Int.self, forKey: .startingHealth)
        startingEnergy = try container.decode(Int.self, forKey: .startingEnergy)
        spawn = try container.decodeIfPresent(SpawnCoord.self, forKey: .spawn)
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? .empty
        sprite = try container.decodeIfPresent(SpriteConfig.self, forKey: .sprite)
        combatSprite = try container.decodeIfPresent(SpriteConfig.self, forKey: .combatSprite)
    }

    nonisolated static let fallback = PlayerConfig(
        letter: "P",
        startingHealth: 1,
        startingEnergy: 2,
        spawn: nil,
        fx: .empty,
        sprite: nil,
        combatSprite: nil
    )

    func validate() throws {
        guard !letter.isEmpty else {
            throw PlayerConfigError.invalid("letter must be non-empty")
        }
        guard startingHealth >= 0 else {
            throw PlayerConfigError.invalid("starting_health must be >= 0")
        }
        guard startingEnergy >= 0 else {
            throw PlayerConfigError.invalid("starting_energy must be >= 0")
        }
    }

    static func loadFromBundle(
        named name: String = "player",
        withExtension ext: String = "yaml"
    ) throws -> PlayerConfig {
        let data = try ConfigStore.data(at: .config(name))
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> PlayerConfig {
        do {
            return try YAMLDecoder().decode(PlayerConfig.self, from: data)
        } catch let error as PlayerConfigError {
            throw error
        } catch {
            throw PlayerConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> PlayerConfig {
        try decode(from: Data(yaml.utf8))
    }
}

nonisolated enum PlayerConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
