import Foundation

struct GameWorld: Sendable, WorldPersistable {
    let width: Int
    let height: Int
    let storyCount: Int
    private(set) var tiles: [[[Tile]]]
    private(set) var entities: [GameEntity]
    let spawn: GridCoord

    init(
        width: Int,
        height: Int,
        storyCount: Int = 2,
        tiles: [[[Tile]]],
        entities: [GameEntity],
        spawn: GridCoord
    ) {
        self.width = width
        self.height = height
        self.storyCount = storyCount
        self.tiles = tiles
        self.entities = entities
        self.spawn = spawn
    }

    func isInBounds(_ coord: GridCoord) -> Bool {
        coord.x >= 0 && coord.x < width &&
        coord.y >= 0 && coord.y < height &&
        coord.story >= 0 && coord.story < storyCount
    }

    func tile(at coord: GridCoord) -> Tile? {
        guard isInBounds(coord) else { return nil }
        return tiles[coord.story][coord.y][coord.x]
    }

    mutating func setTile(_ tile: Tile, at coord: GridCoord) {
        guard isInBounds(coord) else { return }
        tiles[coord.story][coord.y][coord.x] = tile
    }

    var playerIndex: Int? {
        entities.firstIndex(where: \.isPlayer)
    }

    var playerPosition: GridCoord? {
        guard let index = playerIndex else { return nil }
        return entities[index].position
    }

    mutating func setPlayerPosition(_ coord: GridCoord) {
        guard let index = playerIndex else { return }
        entities[index].position = coord
    }

    mutating func respawnPlayer() {
        setPlayerPosition(spawn)
    }

    @discardableResult
    mutating func destroyWall(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord),
              case .wall(let destructible, _, let hasLadder) = tile.kind,
              destructible else {
            return false
        }
        setTile(Tile(kind: .floor(isPit: false)), at: coord)
        if hasLadder {
            // Ladder was on destroyed wall; floor remains without ladder.
        }
        return true
    }

    func isEnterable(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord) else { return false }
        switch tile.kind {
        case .floor, .ramp, .slide:
            return true
        case .wall(_, let hasDoor, let hasLadder):
            return hasDoor || hasLadder
        }
    }

    func lowerStoryEnterable(at coord: GridCoord) -> Bool {
        guard coord.story > 0 else { return false }
        let lower = coord.onStory(coord.story - 1)
        return isEnterable(at: lower)
    }

    mutating func resolvePit(at coord: GridCoord) -> PitResolution {
        guard tile(at: coord)?.isPit == true else { return .none }
        if lowerStoryEnterable(at: coord) {
            let lower = coord.onStory(coord.story - 1)
            setPlayerPosition(lower)
            return .fell(to: lower)
        }
        respawnPlayer()
        return .hazard
    }

    func fingerprint() -> String {
        var parts: [String] = []
        for story in 0..<storyCount {
            for y in 0..<height {
                for x in 0..<width {
                    parts.append(tileDescription(tiles[story][y][x]))
                }
            }
        }
        if let player = playerPosition {
            parts.append("P:\(player.x),\(player.y),\(player.story)")
        }
        return parts.joined(separator: "|")
    }

    private enum CodingKeys: String, CodingKey {
        case width
        case height
        case storyCount
        case tiles
        case entities
        case spawn
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        storyCount = try container.decode(Int.self, forKey: .storyCount)
        tiles = try container.decode([[[Tile]]].self, forKey: .tiles)
        entities = try container.decode([GameEntity].self, forKey: .entities)
        spawn = try container.decode(GridCoord.self, forKey: .spawn)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(storyCount, forKey: .storyCount)
        try container.encode(tiles, forKey: .tiles)
        try container.encode(entities, forKey: .entities)
        try container.encode(spawn, forKey: .spawn)
    }

    private func tileDescription(_ tile: Tile) -> String {
        switch tile.kind {
        case .floor(let isPit):
            return isPit ? "F*" : "F"
        case .wall(let d, let door, let ladder):
            return "W\(d ? "d" : "")\(door ? "D" : "")\(ladder ? "L" : "")"
        case .ramp(let partner, let other):
            return "R\(partner.x),\(partner.y),\(other)"
        case .slide(let partner, let lower):
            return "S\(partner.x),\(partner.y),\(lower)"
        }
    }
}

enum PitResolution: Equatable, Sendable {
    case none
    case fell(to: GridCoord)
    case hazard
}
