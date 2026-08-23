import Foundation

/// One ware in `items.yaml` `merchant:`.
nonisolated struct MerchantItemDefinition: Codable, Equatable, Sendable {
    var minLevel: Int
    var price: Int
    /// Max copies of this ware the player may hold in inventory. `0` means unlimited.
    var limit: Int
    var description: String
    /// Optional use-item FX track id (world HUD tap).
    var sound: String?
    var sprite: SpriteConfig

    enum CodingKeys: String, CodingKey {
        case minLevel = "min_level"
        case price
        case limit
        case description
        case sound
        case sprite
    }

    init(
        minLevel: Int,
        price: Int,
        limit: Int = 0,
        description: String,
        sound: String? = nil,
        sprite: SpriteConfig
    ) {
        self.minLevel = minLevel
        self.price = price
        self.limit = limit
        self.description = description
        self.sound = sound
        self.sprite = sprite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minLevel = try container.decode(Int.self, forKey: .minLevel)
        price = try container.decode(Int.self, forKey: .price)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 0
        description = try container.decode(String.self, forKey: .description)
        sound = try container.decodeIfPresent(String.self, forKey: .sound)
        sprite = try container.decode(SpriteConfig.self, forKey: .sprite)
    }

    /// Displayed cost at a given catalog `order:`.
    func displayedPrice(levelOrder: Int) -> Int {
        price * max(levelOrder, 1)
    }

    /// `limit == 0` is unlimited; otherwise the player may hold at most `limit` copies.
    func canHoldAnother(held: Int) -> Bool {
        Self.canHoldAnother(limit: limit, held: held)
    }

    static func canHoldAnother(limit: Int, held: Int) -> Bool {
        limit <= 0 || held < limit
    }

    static func heldCount(itemID: String, in slots: [String]) -> Int {
        slots.filter { $0 == itemID }.count
    }
}
