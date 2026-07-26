import Foundation

/// Loading-screen sprite definitions from `Resources/Config/UI/loading.yaml`.
struct LoadingSpritesConfig: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var sprite: SpriteConfig
    }

    var kam: Entry
    var logo: Entry
    var yoda: Entry

    var entries: [(id: String, config: SpriteConfig)] {
        [
            (id: "kam", config: kam.sprite),
            (id: "logo", config: logo.sprite),
            (id: "yoda", config: yoda.sprite),
        ]
    }

    static func loadFromBundle(bundle: Bundle = .main) throws -> LoadingSpritesConfig {
        try ConfigStore.load(LoadingSpritesConfig.self, from: .loading, bundle: bundle)
    }
}
