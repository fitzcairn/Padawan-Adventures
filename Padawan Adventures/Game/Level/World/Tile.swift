import Foundation

nonisolated enum TileKind: Equatable, Sendable, WorldPersistable {
    case floor(isPit: Bool)
    case wall
    case gate(minigame: GateMinigameKind)

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
        case minigame
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)

        switch type {
        case .floor:
            self = .floor(isPit: try container.decode(Bool.self, forKey: .isPit))
        case .gate:
            let kind = try container.decodeIfPresent(GateMinigameKind.self, forKey: .minigame)
                ?? .spelling
            self = .gate(minigame: kind)
        case .wall:
            // Legacy `hasLadder` is ignored if present.
            _ = try container.decodeIfPresent(Bool.self, forKey: .hasLadder)
            // Legacy doors become floor openings.
            if try container.decodeIfPresent(Bool.self, forKey: .hasDoor) == true {
                self = .floor(isPit: false)
            } else if try container.decodeIfPresent(Bool.self, forKey: .destructible) == true {
                // Legacy destructible walls become spelling gates.
                self = .gate(minigame: .spelling)
            } else {
                self = .wall
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
        case .wall:
            try container.encode(KindType.wall, forKey: .type)
        case .gate(let minigame):
            try container.encode(KindType.gate, forKey: .type)
            try container.encode(minigame, forKey: .minigame)
        }
    }
}

nonisolated struct Tile: Equatable, Sendable, WorldPersistable {
    var kind: TileKind
    /// Floor tile id from the level's baked floor atlas (`rRRcCC`).
    var floorTileID: String?

    init(kind: TileKind, floorTileID: String? = nil) {
        self.kind = kind
        self.floorTileID = floorTileID
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

    var gateMinigame: GateMinigameKind? {
        if case .gate(let minigame) = kind { return minigame }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case floorTileID
        case terrainID
        case accentTerrainID
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(TileKind.self, forKey: .kind)
        // Prefer the new key; fall back to legacy `terrainID` so old saves decode.
        if let id = try container.decodeIfPresent(String.self, forKey: .floorTileID) {
            floorTileID = id
        } else {
            floorTileID = try container.decodeIfPresent(String.self, forKey: .terrainID)
        }
        // Ignore legacy accent overlays.
        _ = try container.decodeIfPresent(String.self, forKey: .accentTerrainID)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(floorTileID, forKey: .floorTileID)
    }
}
