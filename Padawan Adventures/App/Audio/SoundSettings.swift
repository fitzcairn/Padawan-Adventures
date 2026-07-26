import Foundation
import Yams

/// Global sound settings from `Resources/Config/sound.yaml`.
nonisolated struct SoundSettings: Decodable, Equatable, Sendable {
    var fadeSeconds: Double
    /// Shared one-shot FX (`win`, `lose`, `error`, `correct`, …).
    var fx: SoundEffectTable

    enum CodingKeys: String, CodingKey {
        case fadeSeconds = "fade_seconds"
        case fx
    }

    static let fallback = SoundSettings(
        fadeSeconds: 1.0,
        fx: SoundEffectTable(events: [
            "win": "sfx_win",
            "lose": "sfx_lose",
            "error": "sfx_error",
            "correct": "sfx_correct",
        ])
    )

    init(fadeSeconds: Double, fx: SoundEffectTable = .empty) {
        self.fadeSeconds = fadeSeconds
        self.fx = fx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fadeSeconds = try container.decodeIfPresent(Double.self, forKey: .fadeSeconds)
            ?? Self.fallback.fadeSeconds
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? Self.fallback.fx
    }

    func validate() throws {
        guard fadeSeconds >= 0 else {
            throw MusicConfigError.invalid("fade_seconds must be >= 0")
        }
    }

    static func loadFromBundle(
        named name: String = "sound",
        withExtension ext: String = "yaml"
    ) throws -> SoundSettings {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw MusicConfigError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> SoundSettings {
        do {
            return try YAMLDecoder().decode(SoundSettings.self, from: data)
        } catch let error as MusicConfigError {
            throw error
        } catch {
            throw MusicConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> SoundSettings {
        try decode(from: Data(yaml.utf8))
    }
}

enum MusicConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
