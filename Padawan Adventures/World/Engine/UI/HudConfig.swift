import Foundation
import Yams

struct HudConfig: Codable, Equatable, Sendable {
    var iconSize: Int
    var iconSpacing: Int
    var edgeMargin: Int
    var scoreTextGap: Int

    enum CodingKeys: String, CodingKey {
        case iconSize = "icon_size"
        case iconSpacing = "icon_spacing"
        case edgeMargin = "edge_margin"
        case scoreTextGap = "score_text_gap"
    }

    static let fallback = HudConfig(
        iconSize: 40,
        iconSpacing: 10,
        edgeMargin: 16,
        scoreTextGap: 10
    )

    func validate() throws {
        guard iconSize > 0 else { throw HudConfigError.invalid("icon_size must be > 0") }
        guard iconSpacing > 0 else { throw HudConfigError.invalid("icon_spacing must be > 0") }
        guard edgeMargin > 0 else { throw HudConfigError.invalid("edge_margin must be > 0") }
        guard scoreTextGap > 0 else { throw HudConfigError.invalid("score_text_gap must be > 0") }
    }

    static func loadFromBundle(
        named name: String = "hud",
        withExtension ext: String = "yaml"
    ) throws -> HudConfig {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw HudConfigError.missingResource
        }
        let data = try Data(contentsOf: url)
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
