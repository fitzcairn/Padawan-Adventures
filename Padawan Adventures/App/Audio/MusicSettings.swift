import Foundation
import Yams

/// Global music settings from `Resources/music.yaml`.
nonisolated struct MusicSettings: Codable, Equatable, Sendable {
    var fadeSeconds: Double

    enum CodingKeys: String, CodingKey {
        case fadeSeconds = "fade_seconds"
    }

    static let fallback = MusicSettings(fadeSeconds: 1.0)

    func validate() throws {
        guard fadeSeconds >= 0 else {
            throw MusicConfigError.invalid("fade_seconds must be >= 0")
        }
    }

    static func loadFromBundle(
        named name: String = "music",
        withExtension ext: String = "yaml"
    ) throws -> MusicSettings {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw MusicConfigError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> MusicSettings {
        do {
            return try YAMLDecoder().decode(MusicSettings.self, from: data)
        } catch let error as MusicConfigError {
            throw error
        } catch {
            throw MusicConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> MusicSettings {
        try decode(from: Data(yaml.utf8))
    }
}

enum MusicConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
