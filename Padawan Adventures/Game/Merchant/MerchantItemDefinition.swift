import Foundation

/// Placeholder shop art until merchant items have sprite sheets.
nonisolated enum MerchantItemShape: String, Codable, Equatable, Sendable, CaseIterable {
    case square
    case circle
    case triangle
}

/// `sprite:` block on a merchant ware (`shape` + use `sound`; not a `SpriteConfig`).
nonisolated struct MerchantSpriteSpec: Codable, Equatable, Sendable {
    var shape: MerchantItemShape
    var sound: String?

    enum CodingKeys: String, CodingKey {
        case shape
        case sound
    }

    init(shape: MerchantItemShape, sound: String? = nil) {
        self.shape = shape
        self.sound = sound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shape = try container.decode(MerchantItemShape.self, forKey: .shape)
        sound = try container.decodeIfPresent(String.self, forKey: .sound)
    }
}

/// One ware in `items.yaml` `merchant:`.
nonisolated struct MerchantItemDefinition: Codable, Equatable, Sendable {
    var minLevel: Int
    var price: Int
    var description: String
    var sprite: MerchantSpriteSpec

    enum CodingKeys: String, CodingKey {
        case minLevel = "min_level"
        case price
        case description
        case sprite
    }

    init(minLevel: Int, price: Int, description: String, sprite: MerchantSpriteSpec) {
        self.minLevel = minLevel
        self.price = price
        self.description = description
        self.sprite = sprite
    }

    /// Displayed cost at a given catalog `order:`.
    func displayedPrice(levelOrder: Int) -> Int {
        price * max(levelOrder, 1)
    }
}
