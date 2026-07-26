import Foundation
import UIKit
import Yams

/// One combat projectile kind keyed by letter in `shotTypes`.
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
    /// Combat countdown duration in seconds.
    var combatTimerSeconds: Double
    /// Time for a shot to travel from enemy to player.
    var shotTravelSeconds: Double
    /// Combat stars required to win the encounter.
    var starsToWin: Int
    /// Combat projectile kinds keyed by display letter (e.g. A/B/C).
    var shotTypes: [String: EnemyShotTypeConfig]
    /// Event key → sound track basename (`Resources/Audio/FX/`).
    var fx: SoundEffectTable

    enum CodingKeys: String, CodingKey {
        case letter
        case color
        case tilesPerSecond = "tiles_per_second"
        case forgetSeconds = "forget_seconds"
        case combatTimerSeconds = "combat_timer_seconds"
        case shotTravelSeconds = "shot_travel_seconds"
        case starsToWin = "stars_to_win"
        case shotTypes = "shot_types"
        case fx
    }

    init(
        letter: String,
        color: String,
        tilesPerSecond: Double,
        forgetSeconds: Double,
        combatTimerSeconds: Double = 10,
        shotTravelSeconds: Double = 3.2,
        starsToWin: Int = 10,
        shotTypes: [String: EnemyShotTypeConfig] = EnemyTypeConfig.fallbackShotTypes,
        fx: SoundEffectTable = .empty
    ) {
        self.letter = letter
        self.color = color
        self.tilesPerSecond = tilesPerSecond
        self.forgetSeconds = forgetSeconds
        self.combatTimerSeconds = combatTimerSeconds
        self.shotTravelSeconds = shotTravelSeconds
        self.starsToWin = starsToWin
        self.shotTypes = shotTypes
        self.fx = fx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        letter = try container.decode(String.self, forKey: .letter)
        color = try container.decode(String.self, forKey: .color)
        tilesPerSecond = try container.decode(Double.self, forKey: .tilesPerSecond)
        forgetSeconds = try container.decode(Double.self, forKey: .forgetSeconds)
        combatTimerSeconds = try container.decodeIfPresent(Double.self, forKey: .combatTimerSeconds) ?? 10
        shotTravelSeconds = try container.decodeIfPresent(Double.self, forKey: .shotTravelSeconds) ?? 3.2
        starsToWin = try container.decodeIfPresent(Int.self, forKey: .starsToWin) ?? 10
        shotTypes = try container.decodeIfPresent([String: EnemyShotTypeConfig].self, forKey: .shotTypes)
            ?? EnemyTypeConfig.fallbackShotTypes
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? .empty
    }

    /// Fallback A/B/C letter-name shots used by hand-built configs / tests.
    static let fallbackShotTypes: [String: EnemyShotTypeConfig] = [
        "A": EnemyShotTypeConfig(trackBasename: "sfx_letter_a_name"),
        "B": EnemyShotTypeConfig(trackBasename: "sfx_letter_b_name"),
        "C": EnemyShotTypeConfig(trackBasename: "sfx_letter_c_name"),
    ]

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
        guard combatTimerSeconds > 0 else {
            throw EnemyConfigError.invalid("\(typeID).combat_timer_seconds must be > 0")
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

nonisolated struct EnemyConfig: Codable, Equatable, Sendable {
    /// Max seconds a combat slash stays active after the initial tap.
    var slashMaxSeconds: Double
    var enemies: [String: EnemyTypeConfig]

    enum CodingKeys: String, CodingKey {
        case slashMaxSeconds = "slash_max_seconds"
        case enemies
    }

    nonisolated static let fallbackSlashMaxSeconds: Double = 0.5

    nonisolated static let fallback = EnemyConfig(
        slashMaxSeconds: fallbackSlashMaxSeconds,
        enemies: [
            "horranth": EnemyTypeConfig(
                letter: "E",
                color: "#FF0000",
                tilesPerSecond: 1.0,
                forgetSeconds: 3.0,
                combatTimerSeconds: 10,
                shotTravelSeconds: 3.2,
                starsToWin: 10,
                shotTypes: EnemyTypeConfig.fallbackShotTypes,
                fx: .empty
            ),
        ]
    )

    init(
        slashMaxSeconds: Double = fallbackSlashMaxSeconds,
        enemies: [String: EnemyTypeConfig]
    ) {
        self.slashMaxSeconds = slashMaxSeconds
        self.enemies = enemies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slashMaxSeconds = try container.decodeIfPresent(Double.self, forKey: .slashMaxSeconds)
            ?? Self.fallbackSlashMaxSeconds
        enemies = try container.decode([String: EnemyTypeConfig].self, forKey: .enemies)
    }

    func validate() throws {
        guard slashMaxSeconds > 0 else {
            throw EnemyConfigError.invalid("slash_max_seconds must be > 0")
        }
        guard !enemies.isEmpty else {
            throw EnemyConfigError.invalid("enemies must not be empty")
        }
        for (id, type) in enemies {
            try type.validate(typeID: id)
        }
    }

    func type(named id: String) -> EnemyTypeConfig? {
        enemies[id]
    }

    static func loadFromBundle(
        named name: String = "enemies",
        withExtension ext: String = "yaml"
    ) throws -> EnemyConfig {
        let data = try ConfigStore.data(
            at: ConfigPath(basename: name, subdirectory: "Catalogs")
        )
        return try decode(from: data)
    }

    static func decode(
        from data: Data,
        letterCatalog: LetterCatalog? = nil
    ) throws -> EnemyConfig {
        do {
            let letters = try letterCatalog ?? Self.loadLetterCatalog()
            var tree = try ConfigStore.rawTree(
                from: data,
                parentDataNamed: nil,
                fileLabel: "enemies.yaml"
            )
            try resolveShotLetters(in: &tree, letterCatalog: letters)
            let yaml = try Yams.dump(object: tree)
            let config = try YAMLDecoder().decode(EnemyConfigDTO.self, from: yaml).asEnemyConfig()
            try config.validate()
            return config
        } catch let error as EnemyConfigError {
            throw error
        } catch let error as ConfigError {
            throw EnemyConfigError.decodeFailed
        } catch {
            throw EnemyConfigError.decodeFailed
        }
    }

    static func decode(
        from yaml: String,
        letterCatalog: LetterCatalog? = nil
    ) throws -> EnemyConfig {
        try decode(from: Data(yaml.utf8), letterCatalog: letterCatalog)
    }

    private static func loadLetterCatalog() throws -> LetterCatalog {
        do {
            return try LetterCatalog.loadFromBundle()
        } catch {
            return .fallback
        }
    }

    /// Replaces each enemy's `shot_letters: [a, b, …]` with a `shot_types` map resolved
    /// through the letter catalog (`a` → key `A`, shoot track = letter `name`).
    private static func resolveShotLetters(
        in tree: inout [String: Any],
        letterCatalog: LetterCatalog
    ) throws {
        guard var enemies = ConfigStore.asStringKeyedDictionary(tree["enemies"] as Any?) else {
            return
        }
        for (enemyID, entryValue) in enemies {
            guard var entry = ConfigStore.asStringKeyedDictionary(entryValue) else { continue }
            guard let rawLetters = entry["shot_letters"] as? [Any] else {
                // Allow hand-built YAML that already has shot_types (tests).
                continue
            }
            var shotTypes: [String: Any] = [:]
            for raw in rawLetters {
                let id = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !id.isEmpty else {
                    throw EnemyConfigError.invalid("\(enemyID).shot_letters entries must be non-empty")
                }
                guard let letter = letterCatalog.letter(named: id) else {
                    throw EnemyConfigError.invalid(
                        "\(enemyID).shot_letters.\(id) is not in the letter catalog"
                    )
                }
                let key = id.uppercased()
                shotTypes[key] = ["fx": letter.name]
            }
            entry.removeValue(forKey: "shot_letters")
            entry["shot_types"] = shotTypes
            enemies[enemyID] = entry
        }
        tree["enemies"] = enemies
    }
}

/// Intermediate decode shape that still accepts injected `shot_types` maps.
private nonisolated struct EnemyConfigDTO: Decodable, Sendable {
    var slashMaxSeconds: Double?
    var enemies: [String: EnemyTypeConfigDTO]

    enum CodingKeys: String, CodingKey {
        case slashMaxSeconds = "slash_max_seconds"
        case enemies
    }

    nonisolated func asEnemyConfig() -> EnemyConfig {
        EnemyConfig(
            slashMaxSeconds: slashMaxSeconds ?? EnemyConfig.fallbackSlashMaxSeconds,
            enemies: enemies.mapValues { $0.asEnemyTypeConfig() }
        )
    }
}

private nonisolated struct EnemyTypeConfigDTO: Decodable, Sendable {
    var letter: String
    var color: String
    var tilesPerSecond: Double
    var forgetSeconds: Double
    var combatTimerSeconds: Double?
    var shotTravelSeconds: Double?
    var starsToWin: Int?
    var shotTypes: [String: EnemyShotTypeConfig]?
    var fx: SoundEffectTable?

    enum CodingKeys: String, CodingKey {
        case letter
        case color
        case tilesPerSecond = "tiles_per_second"
        case forgetSeconds = "forget_seconds"
        case combatTimerSeconds = "combat_timer_seconds"
        case shotTravelSeconds = "shot_travel_seconds"
        case starsToWin = "stars_to_win"
        case shotTypes = "shot_types"
        case fx
    }

    nonisolated func asEnemyTypeConfig() -> EnemyTypeConfig {
        EnemyTypeConfig(
            letter: letter,
            color: color,
            tilesPerSecond: tilesPerSecond,
            forgetSeconds: forgetSeconds,
            combatTimerSeconds: combatTimerSeconds ?? 10,
            shotTravelSeconds: shotTravelSeconds ?? 3.2,
            starsToWin: starsToWin ?? 10,
            shotTypes: shotTypes ?? EnemyTypeConfig.fallbackShotTypes,
            fx: fx ?? .empty
        )
    }
}

nonisolated enum EnemyConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}

extension UIColor {
    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA` hex strings.
    nonisolated convenience init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 3 || raw.count == 6 || raw.count == 8,
              let value = UInt64(raw, radix: 16) else {
            return nil
        }

        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let a: CGFloat

        switch raw.count {
        case 3:
            r = CGFloat((value >> 8) & 0xF) / 15
            g = CGFloat((value >> 4) & 0xF) / 15
            b = CGFloat(value & 0xF) / 15
            a = 1
        case 6:
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        default:
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
