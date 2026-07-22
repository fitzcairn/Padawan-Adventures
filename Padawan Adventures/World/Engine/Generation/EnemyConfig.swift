import Foundation
import UIKit
import Yams

nonisolated struct EnemyTypeConfig: Codable, Equatable, Sendable {
    var letter: String
    var color: String
    var tilesPerSecond: Double
    var forgetSeconds: Double
    /// Event key → sound track basename (`Resources/Audio/`).
    var fx: SoundEffectTable

    enum CodingKeys: String, CodingKey {
        case letter
        case color
        case tilesPerSecond = "tiles_per_second"
        case forgetSeconds = "forget_seconds"
        case fx
    }

    init(
        letter: String,
        color: String,
        tilesPerSecond: Double,
        forgetSeconds: Double,
        fx: SoundEffectTable = .empty
    ) {
        self.letter = letter
        self.color = color
        self.tilesPerSecond = tilesPerSecond
        self.forgetSeconds = forgetSeconds
        self.fx = fx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        letter = try container.decode(String.self, forKey: .letter)
        color = try container.decode(String.self, forKey: .color)
        tilesPerSecond = try container.decode(Double.self, forKey: .tilesPerSecond)
        forgetSeconds = try container.decode(Double.self, forKey: .forgetSeconds)
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? .empty
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
    }

    var fillColor: UIColor {
        UIColor(hex: color) ?? .red
    }

    var letterCharacter: Character {
        letter.first ?? "E"
    }
}

nonisolated struct EnemyConfig: Codable, Equatable, Sendable {
    var types: [String: EnemyTypeConfig]

    nonisolated static let fallback = EnemyConfig(
        types: [
            "grunt": EnemyTypeConfig(
                letter: "E",
                color: "#FF0000",
                tilesPerSecond: 1.0,
                forgetSeconds: 3.0,
                fx: .empty
            ),
        ]
    )

    func validate() throws {
        guard !types.isEmpty else {
            throw EnemyConfigError.invalid("types must not be empty")
        }
        for (id, type) in types {
            try type.validate(typeID: id)
        }
    }

    func type(named id: String) -> EnemyTypeConfig? {
        types[id]
    }

    static func loadFromBundle(
        named name: String = "enemy",
        withExtension ext: String = "yaml"
    ) throws -> EnemyConfig {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw EnemyConfigError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> EnemyConfig {
        do {
            return try YAMLDecoder().decode(EnemyConfig.self, from: data)
        } catch let error as EnemyConfigError {
            throw error
        } catch {
            throw EnemyConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> EnemyConfig {
        try decode(from: Data(yaml.utf8))
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
