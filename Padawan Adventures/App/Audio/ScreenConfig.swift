import Foundation
import Yams

/// Per-screen settings from `Resources/Config/Screens/<name>.yaml`.
nonisolated struct ScreenConfig: Codable, Equatable, Sendable {
    /// Raw `music:` value; interpret with `MusicCue.parse`.
    var music: String?

    static let fallback = ScreenConfig(music: nil)

    static let subdirectory = "Screens"

    var musicCue: MusicCue {
        MusicCue.parse(music)
    }

    static func loadFromBundle(
        named name: String,
        withExtension ext: String = "yaml",
        subdirectory: String? = subdirectory
    ) throws -> ScreenConfig {
        let data = try resourceData(named: name, withExtension: ext, subdirectory: subdirectory)
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> ScreenConfig {
        do {
            return try YAMLDecoder().decode(ScreenConfig.self, from: data)
        } catch {
            throw MusicConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> ScreenConfig {
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
            throw MusicConfigError.missingResource
        }
        return try Data(contentsOf: url)
    }
}
