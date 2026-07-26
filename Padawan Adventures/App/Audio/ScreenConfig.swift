import Foundation
import Yams

/// All screens from `Resources/Config/screens.yaml`.
nonisolated struct ScreensConfig: Codable, Equatable, Sendable {
    var version: Int
    var screens: [String: ScreenConfig]

    static let fallback = ScreensConfig(version: 1, screens: [:])

    static func loadFromBundle(bundle: Bundle = .main) throws -> ScreensConfig {
        try ConfigStore.load(ScreensConfig.self, from: .screens, bundle: bundle)
    }

    static func decode(from data: Data) throws -> ScreensConfig {
        do {
            return try YAMLDecoder().decode(ScreensConfig.self, from: data)
        } catch {
            throw MusicConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> ScreensConfig {
        try decode(from: Data(yaml.utf8))
    }
}

/// Per-screen settings from `Resources/Config/screens.yaml` (`screens.<name>`).
nonisolated struct ScreenConfig: Codable, Equatable, Sendable {
    /// Raw `music:` value; interpret with `MusicCue.parse`.
    var music: String?
    /// Still image basename under `Resources/Backgrounds/` for this screen.
    var background: String?

    static let fallback = ScreenConfig(music: nil, background: nil)

    var musicCue: MusicCue {
        MusicCue.parse(music)
    }

    static func loadFromBundle(named name: String) throws -> ScreenConfig {
        let all = try ScreensConfig.loadFromBundle()
        guard let config = all.screens[name] else {
            throw ConfigError.missingResource(file: "screens.yaml#\(name)")
        }
        return config
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
}
