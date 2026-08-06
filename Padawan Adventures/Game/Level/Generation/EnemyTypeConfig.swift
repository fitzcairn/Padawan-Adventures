import Foundation
import UIKit
import Yams

nonisolated struct EnemyShotTypeConfig: Codable, Equatable, Sendable {
    /// Cue SFX table; basename YAML form becomes `{ shoot: <basename> }`.
    var fx: SoundEffectTable

    enum CodingKeys: String, CodingKey {
        case fx
    }

    init(fx: SoundEffectTable = .empty) {
        self.fx = fx
    }

    init(trackBasename: String) {
        fx = SoundEffectTable(events: ["shoot": trackBasename])
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let table = try? container.decode(SoundEffectTable.self, forKey: .fx) {
            fx = table
        } else if let basename = try container.decodeIfPresent(String.self, forKey: .fx) {
            let trimmed = basename.trimmingCharacters(in: .whitespacesAndNewlines)
            fx = trimmed.isEmpty ? .empty : SoundEffectTable(events: ["shoot": trimmed])
        } else {
            fx = .empty
        }
    }

    func validate(typeID: String, letter: String) throws {
        guard !letter.isEmpty else {
            throw EnemyConfigError.invalid("\(typeID).shot_types key must be non-empty")
        }
        guard fx.trackID(for: "shoot") != nil else {
            throw EnemyConfigError.invalid("\(typeID).shot_types.\(letter).fx must name a shoot track")
        }
    }
}

nonisolated struct EnemyTypeConfig: Codable, Equatable, Sendable {
    var letter: String
    var color: String
    var tilesPerSecond: Double
    var forgetSeconds: Double
    /// Reference fight length in seconds used to pace shot spawns.
    var shotPacingSeconds: Double
    /// Time for a shot to travel from enemy to player.
    var shotTravelSeconds: Double
    /// Combat stars required to win the encounter.
    var starsToWin: Int
    /// Combat projectile kinds keyed by display letter (e.g. A/B/C).
    var shotTypes: [String: EnemyShotTypeConfig]
    /// Event key → sound track basename (`Resources/Audio/FX/`).
    var fx: SoundEffectTable
    /// Shared sprite id from the file's `sprites:` map; nil renders the placeholder shape.
    var sprite: String?

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
    }

    init(
        letter: String,
        color: String,
        tilesPerSecond: Double,
        forgetSeconds: Double,
        shotPacingSeconds: Double = 10,
        shotTravelSeconds: Double = 3.2,
        starsToWin: Int = 10,
        shotTypes: [String: EnemyShotTypeConfig] = EnemyTypeConfig.fallbackShotTypes,
        fx: SoundEffectTable = .empty,
        sprite: String? = nil
    ) {
        self.letter = letter
        self.color = color
        self.tilesPerSecond = tilesPerSecond
        self.forgetSeconds = forgetSeconds
        self.shotPacingSeconds = shotPacingSeconds
        self.shotTravelSeconds = shotTravelSeconds
        self.starsToWin = starsToWin
        self.shotTypes = shotTypes
        self.fx = fx
        self.sprite = sprite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        letter = try container.decode(String.self, forKey: .letter)
        color = try container.decode(String.self, forKey: .color)
        tilesPerSecond = try container.decode(Double.self, forKey: .tilesPerSecond)
        forgetSeconds = try container.decode(Double.self, forKey: .forgetSeconds)
        shotPacingSeconds = try container.decodeIfPresent(Double.self, forKey: .shotPacingSeconds) ?? 10
        shotTravelSeconds = try container.decodeIfPresent(Double.self, forKey: .shotTravelSeconds) ?? 3.2
        starsToWin = try container.decodeIfPresent(Int.self, forKey: .starsToWin) ?? 10
        shotTypes = try container.decodeIfPresent([String: EnemyShotTypeConfig].self, forKey: .shotTypes)
            ?? EnemyTypeConfig.fallbackShotTypes
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? .empty
        sprite = try container.decodeIfPresent(String.self, forKey: .sprite)
    }

    /// Level-1 letters used when YAML omits `shot_types` (hand-built configs / tests).
    /// Runtime fights overwrite this from `LevelVocabularyPool.letters`.
    static let fallbackShotTypes: [String: EnemyShotTypeConfig] = shotTypes(
        fromLetters: ["s", "a", "t", "p", "i", "n"]
    )

    /// Uppercase-keyed shot map from single-character graphemes (`a` → `"A"` + name track).
    static func shotTypes(from pool: LevelVocabularyPool) -> [String: EnemyShotTypeConfig] {
        var out: [String: EnemyShotTypeConfig] = [:]
        for entry in pool.allGraphemes where entry.grapheme.count == 1 {
            let track = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !track.isEmpty else { continue }
            out[entry.grapheme.uppercased()] = EnemyShotTypeConfig(trackBasename: track)
        }
        return out
    }

    /// Builds shot types for explicit lowercase letter ids (fallback / tests).
    static func shotTypes(fromLetters letters: [String]) -> [String: EnemyShotTypeConfig] {
        var out: [String: EnemyShotTypeConfig] = [:]
        for raw in letters {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard id.count == 1 else { continue }
            out[id.uppercased()] = EnemyShotTypeConfig(trackBasename: "sfx_letter_\(id)_name")
        }
        return out
    }

    /// Copy with slash shot pool replaced by the level's single-character letters.
    func withShotTypes(from pool: LevelVocabularyPool) -> EnemyTypeConfig {
        let synthesized = Self.shotTypes(from: pool)
        guard !synthesized.isEmpty else { return self }
        var copy = self
        copy.shotTypes = synthesized
        return copy
    }

    /// Stable letter keys for combat random selection.
    var shotLetters: [String] {
        shotTypes.keys.sorted()
    }

    func validate(typeID: String) throws {
        guard !letter.isEmpty else {
            throw EnemyConfigError.invalid("\(typeID).letter must be non-empty")
        }
        guard UIColor(hex: color) != nil else {
            throw EnemyConfigError.invalid("\(typeID).color must be a hex color like #RRGGBB")
        }
        guard tilesPerSecond > 0 else {
            throw EnemyConfigError.invalid("\(typeID).tiles_per_second must be > 0")
        }
        guard forgetSeconds >= 0 else {
            throw EnemyConfigError.invalid("\(typeID).forget_seconds must be >= 0")
        }
        guard shotPacingSeconds > 0 else {
            throw EnemyConfigError.invalid("\(typeID).shot_pacing_seconds must be > 0")
        }
        guard shotTravelSeconds > 0 else {
            throw EnemyConfigError.invalid("\(typeID).shot_travel_seconds must be > 0")
        }
        guard starsToWin >= 1 else {
            throw EnemyConfigError.invalid("\(typeID).stars_to_win must be >= 1")
        }
        guard !shotTypes.isEmpty else {
            throw EnemyConfigError.invalid("\(typeID).shot_types must not be empty")
        }
        for (shotLetter, shotType) in shotTypes {
            try shotType.validate(typeID: typeID, letter: shotLetter)
        }
    }

    var fillColor: UIColor {
        UIColor(hex: color) ?? .red
    }

    var letterCharacter: Character {
        letter.first ?? "E"
    }
}
