import Foundation

/// Vector flyover sprite from `Resources/Config/UI/vector.yaml`.
struct VectorSpritesConfig: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var sprite: SpriteConfig
    }

    static let libraryID = "vector"
    static let flyAnimation = "fly"

    var ship: Entry

    var entries: [(id: String, config: SpriteConfig)] {
        [(id: Self.libraryID, config: ship.sprite)]
    }

    static func loadFromBundle(bundle: Bundle = .main) throws -> VectorSpritesConfig {
        try ConfigStore.load(VectorSpritesConfig.self, from: .vector, bundle: bundle)
    }
}
