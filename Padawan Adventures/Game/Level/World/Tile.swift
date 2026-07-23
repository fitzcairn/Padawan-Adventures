import Foundation

nonisolated enum TileKind: Equatable, Sendable, WorldPersistable {
    case floor(isPit: Bool)
    case wall(destructible: Bool)
    case gate

    private enum KindType: String, Codable {
        case floor
        case wall
        case gate
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
        case .gate:
            self = .gate
        case .wall:
            // Legacy `hasLadder` is ignored if present.
            _ = try container.decodeIfPresent(Bool.self, forKey: .hasLadder)
            // Legacy doors become floor openings.
            if try container.decodeIfPresent(Bool.self, forKey: .hasDoor) == true {
                self = .floor(isPit: false)
            } else {
                self = .wall(destructible: try container.decode(Bool.self, forKey: .destructible))
            }
        case .ramp, .slide:
            // Legacy connector tiles become ordinary floors.
            self = .floor(isPit: false)
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .floor(let isPit):
            try container.encode(KindType.floor, forKey: .type)
            try container.encode(isPit, forKey: .isPit)
        case .wall(let destructible):
            try container.encode(KindType.wall, forKey: .type)
            try container.encode(destructible, forKey: .destructible)
        case .gate:
            try container.encode(KindType.gate, forKey: .type)
        }
    }
}

nonisolated struct Tile: Equatable, Sendable, WorldPersistable {
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

    var isGate: Bool {
        if case .gate = kind { return true }
        return false
    }

    var isDestructibleWall: Bool {
        if case .wall(true) = kind { return true }
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
