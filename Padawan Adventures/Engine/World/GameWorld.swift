import Foundation

struct GameWorld: Sendable, WorldPersistable {
    let width: Int
    let height: Int
    let storyCount: Int
    private(set) var tiles: [[[Tile]]]
    private(set) var entities: [GameEntity]
    let spawn: GridCoord
    var healthCount: Int
    var energyCount: Int

    init(
        width: Int,
        height: Int,
        storyCount: Int = 1,
        tiles: [[[Tile]]],
        entities: [GameEntity],
        spawn: GridCoord,
        healthCount: Int = 0,
        energyCount: Int = 0
    ) {
        self.width = width
        self.height = height
        self.storyCount = storyCount
        self.tiles = tiles
        self.entities = entities
        self.spawn = spawn
        self.healthCount = healthCount
        self.energyCount = energyCount
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

    func entityIndex(id: UUID) -> Int? {
        entities.firstIndex { $0.id == id }
    }

    func entity(id: UUID) -> GameEntity? {
        guard let index = entityIndex(id: id) else { return nil }
        return entities[index]
    }

    mutating func setEntityPosition(_ coord: GridCoord, id: UUID) {
        guard let index = entityIndex(id: id) else { return }
        entities[index].position = coord
    }

    @discardableResult
    mutating func removeEntity(id: UUID) -> Bool {
        guard let index = entityIndex(id: id) else { return false }
        entities.remove(at: index)
        return true
    }

    /// First enemy occupying the same tile as the player, if any.
    func enemyInContactWithPlayer() -> GameEntity? {
        guard let playerPosition else { return nil }
        return entities.first { entity in
            entity.isEnemy && entity.position == playerPosition
        }
    }

    /// First pickup occupying the same tile as the player, if any.
    func pickupInContactWithPlayer() -> GameEntity? {
        guard let playerPosition else { return nil }
        return entities.first { entity in
            entity.isPickup && entity.position == playerPosition
        }
    }

    mutating func respawnPlayer() {
        setPlayerPosition(spawn)
    }

    @discardableResult
    mutating func destroyWall(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord),
              case .wall(let destructible, _) = tile.kind,
              destructible else {
            return false
        }
        setTile(Tile(kind: .floor(isPit: false)), at: coord)
        return true
    }

    func isEnterable(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord) else { return false }
        switch tile.kind {
        case .floor:
            return true
        case .wall(_, let hasDoor):
            return hasDoor
        }
    }

    /// Walkable for path edges: enterable tiles (including pits). Doors remain walkable.
    func isWalkable(at coord: GridCoord) -> Bool {
        isEnterable(at: coord)
    }

    /// Valid tap / movement destination: floor (including pits) — never plain wall or door.
    func isValidMovementGoal(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord) else { return false }
        if case .floor = tile.kind { return true }
        return false
    }

    /// Resolves a tap to a valid movement goal on the same story (BFS to nearest if needed).
    func nearestValidMovementGoal(from coord: GridCoord) -> GridCoord? {
        guard isInBounds(coord) else { return nil }
        if isValidMovementGoal(at: coord) { return coord }

        var queue = [coord]
        var visited: Set<GridCoord> = [coord]
        var head = 0

        while head < queue.count {
            let current = queue[head]
            head += 1
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard next.story == coord.story, isInBounds(next), !visited.contains(next) else { continue }
                if isValidMovementGoal(at: next) { return next }
                visited.insert(next)
                queue.append(next)
            }
        }
        return nil
    }

    mutating func resolvePit(at coord: GridCoord) -> PitResolution {
        guard tile(at: coord)?.isPit == true else { return .none }
        // Stay on the pit tile; UI handles the encounter (no auto-respawn).
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
        case healthCount
        case energyCount
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        storyCount = try container.decode(Int.self, forKey: .storyCount)
        tiles = try container.decode([[[Tile]]].self, forKey: .tiles)
        entities = try container.decode([GameEntity].self, forKey: .entities)
        spawn = try container.decode(GridCoord.self, forKey: .spawn)
        healthCount = try container.decodeIfPresent(Int.self, forKey: .healthCount) ?? 0
        energyCount = try container.decodeIfPresent(Int.self, forKey: .energyCount) ?? 0
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(storyCount, forKey: .storyCount)
        try container.encode(tiles, forKey: .tiles)
        try container.encode(entities, forKey: .entities)
        try container.encode(spawn, forKey: .spawn)
        try container.encode(healthCount, forKey: .healthCount)
        try container.encode(energyCount, forKey: .energyCount)
    }

    private func tileDescription(_ tile: Tile) -> String {
        switch tile.kind {
        case .floor(let isPit):
            return isPit ? "F*" : "F"
        case .wall(let d, let door):
            return "W\(d ? "d" : "")\(door ? "D" : "")"
        }
    }
}

enum PitResolution: Equatable, Sendable {
    case none
    case hazard
}
