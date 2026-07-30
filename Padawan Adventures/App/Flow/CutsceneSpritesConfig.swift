import Foundation

/// Cutscene sprite definitions from `Resources/Config/UI/cutscene.yaml`.
struct CutsceneSpritesConfig: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var sprite: SpriteConfig
    }

    static let kamID = "cutscene_kam"
    static let yodaID = "cutscene_yoda"

    var kam: Entry
    var yoda: Entry

    var entries: [(id: String, config: SpriteConfig)] {
        [
            (id: Self.kamID, config: kam.sprite),
            (id: Self.yodaID, config: yoda.sprite),
        ]
    }

    static func loadFromBundle(bundle: Bundle = .main) throws -> CutsceneSpritesConfig {
        try ConfigStore.load(CutsceneSpritesConfig.self, from: .cutscene, bundle: bundle)
    }
}
