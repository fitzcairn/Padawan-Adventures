import Foundation
import Yams

struct HudConfig: Codable, Equatable, Sendable {
    var iconSize: Int
    var iconSpacing: Int
    var scoreTextGap: Int

    enum CodingKeys: String, CodingKey {
        case iconSize = "icon_size_points"
        case iconSpacing = "icon_spacing_points"
        case scoreTextGap = "score_text_gap_points"
    }

    static let fallback = HudConfig(
        iconSize: 40,
        iconSpacing: 10,
        scoreTextGap: 10
    )

    func validate() throws {
        guard iconSize > 0 else { throw HudConfigError.invalid("icon_size_points must be > 0") }
        guard iconSpacing > 0 else { throw HudConfigError.invalid("icon_spacing_points must be > 0") }
        guard scoreTextGap > 0 else { throw HudConfigError.invalid("score_text_gap_points must be > 0") }
    }

    static func loadFromBundle(
        named name: String = "hud",
        withExtension ext: String = "yaml"
    ) throws -> HudConfig {
        let data = try ConfigStore.data(at: .config(name))
        return try decode(from: data)
    }

    static func decode(from data: Data) throws -> HudConfig {
        do {
            return try YAMLDecoder().decode(HudConfig.self, from: data)
        } catch let error as HudConfigError {
            throw error
        } catch {
            throw HudConfigError.decodeFailed
        }
    }

    static func decode(from yaml: String) throws -> HudConfig {
        try decode(from: Data(yaml.utf8))
    }
}

enum HudConfigError: Error, Equatable {
    case missingResource
    case decodeFailed
    case invalid(String)
}
