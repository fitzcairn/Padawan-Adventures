import Foundation
import Yams

struct PlayerConfig: Codable, Equatable, Sendable {
    var letter: String
    var startingHealth: Int
    var startingEnergy: Int
    var spawn: SpawnCoord?

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
    }

    init(
        letter: String,
        startingHealth: Int = 0,
        startingEnergy: Int = 0,
        spawn: SpawnCoord? = nil
    ) {
        self.letter = letter
        self.startingHealth = startingHealth
        self.startingEnergy = startingEnergy
        self.spawn = spawn
    }

    static let fallback = PlayerConfig(
        letter: "P",
        startingHealth: 3,
        startingEnergy: 2,
        spawn: nil
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
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw PlayerConfigError.missingResource
        }
        let data = try Data(contentsOf: url)
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

enum PlayerConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
