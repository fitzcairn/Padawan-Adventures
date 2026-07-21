import Foundation

enum TileKind: Equatable, Sendable, WorldPersistable {
    case floor(isPit: Bool)
    case wall(destructible: Bool, hasDoor: Bool, hasLadder: Bool)
    case ramp(partner: GridCoord, otherStory: Int)
    case slide(partner: GridCoord, lowerStory: Int)

    private enum KindType: String, Codable {
        case floor
        case wall
        case ramp
        case slide
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case isPit
        case destructible
        case hasDoor
        case hasLadder
        case partner
        case otherStory
        case lowerStory
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)

        switch type {
        case .floor:
            self = .floor(isPit: try container.decode(Bool.self, forKey: .isPit))
        case .wall:
            self = .wall(
                destructible: try container.decode(Bool.self, forKey: .destructible),
                hasDoor: try container.decode(Bool.self, forKey: .hasDoor),
                hasLadder: try container.decode(Bool.self, forKey: .hasLadder)
            )
        case .ramp:
            self = .ramp(
                partner: try container.decode(GridCoord.self, forKey: .partner),
                otherStory: try container.decode(Int.self, forKey: .otherStory)
            )
        case .slide:
            self = .slide(
                partner: try container.decode(GridCoord.self, forKey: .partner),
                lowerStory: try container.decode(Int.self, forKey: .lowerStory)
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .floor(let isPit):
            try container.encode(KindType.floor, forKey: .type)
            try container.encode(isPit, forKey: .isPit)
        case .wall(let destructible, let hasDoor, let hasLadder):
            try container.encode(KindType.wall, forKey: .type)
            try container.encode(destructible, forKey: .destructible)
            try container.encode(hasDoor, forKey: .hasDoor)
            try container.encode(hasLadder, forKey: .hasLadder)
        case .ramp(let partner, let otherStory):
            try container.encode(KindType.ramp, forKey: .type)
            try container.encode(partner, forKey: .partner)
            try container.encode(otherStory, forKey: .otherStory)
        case .slide(let partner, let lowerStory):
            try container.encode(KindType.slide, forKey: .type)
            try container.encode(partner, forKey: .partner)
            try container.encode(lowerStory, forKey: .lowerStory)
        }
    }
}

struct Tile: Equatable, Sendable, WorldPersistable {
    var kind: TileKind

    init(kind: TileKind) {
        self.kind = kind
    }

    var isPit: Bool {
        if case .floor(isPit: true) = kind { return true }
        return false
    }

    var isWall: Bool {
        if case .wall = kind { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(TileKind.self, forKey: .kind)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
    }
}
