import Foundation

nonisolated struct GameWorld: Sendable, WorldPersistable {
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

    /// Opens a destructible wall cell and every orthogonally contiguous soft wall in its group.
    @discardableResult
    mutating func destroyWall(at coord: GridCoord) -> Bool {
        guard tile(at: coord)?.isDestructibleWall == true else { return false }
        var queue = [coord]
        var visited: Set<GridCoord> = [coord]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            setTile(Tile(kind: .floor(isPit: false)), at: current)
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard isInBounds(next), !visited.contains(next) else { continue }
                guard tile(at: next)?.isDestructibleWall == true else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return true
    }

    /// Opens a gate cell and every orthogonally contiguous gate in its barrier strip.
    @discardableResult
    mutating func openGate(at coord: GridCoord) -> Bool {
        guard tile(at: coord)?.isGate == true else { return false }
        var queue = [coord]
        var visited: Set<GridCoord> = [coord]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            setTile(Tile(kind: .floor(isPit: false)), at: current)
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard isInBounds(next), !visited.contains(next) else { continue }
                guard tile(at: next)?.isGate == true else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return true
    }

    /// Fills a pit cell and every orthogonally contiguous pit in its blob into ordinary floor.
    @discardableResult
    mutating func fillPit(at coord: GridCoord) -> Bool {
        guard tile(at: coord)?.isPit == true else { return false }
        var queue = [coord]
        var visited: Set<GridCoord> = [coord]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            setTile(Tile(kind: .floor(isPit: false)), at: current)
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard isInBounds(next), !visited.contains(next) else { continue }
                guard tile(at: next)?.isPit == true else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return true
    }

    func isEnterable(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord) else { return false }
        switch tile.kind {
        case .floor, .gate:
            return true
        case .wall(let destructible):
            return destructible
        }
    }

    /// Walkable for path edges: enterable tiles (including pits, gates, destructible walls).
    func isWalkable(at coord: GridCoord) -> Bool {
        isEnterable(at: coord)
    }

    /// Valid tap / movement destination: floors, destructible walls, and gates.
    func isValidMovementGoal(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord) else { return false }
        switch tile.kind {
        case .floor, .gate:
            return true
        case .wall(let destructible):
            return destructible
        }
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

    /// Nearest non-pit floor on the same story (BFS; may traverse pit tiles).
    func nearestNonPitTile(from coord: GridCoord) -> GridCoord? {
        guard isInBounds(coord) else { return nil }
        if isNonPitFloor(at: coord) { return coord }

        var queue = [coord]
        var visited: Set<GridCoord> = [coord]
        var head = 0

        while head < queue.count {
            let current = queue[head]
            head += 1
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard next.story == coord.story, isInBounds(next), !visited.contains(next) else { continue }
                if isNonPitFloor(at: next) { return next }
                visited.insert(next)
                queue.append(next)
            }
        }
        return nil
    }

    /// Moves the player from a pit onto the nearest non-pit floor tile.
    @discardableResult
    mutating func relocatePlayerOffPit() -> Bool {
        guard let position = playerPosition, tile(at: position)?.isPit == true else { return false }
        guard let safe = nearestNonPitTile(from: position) else { return false }
        setPlayerPosition(safe)
        return true
    }

    /// After defeat restore, push enemies within `maxProximity` tiles to about
    /// `separationDistance` tiles from the player so contact isn't immediate.
    @discardableResult
    mutating func separateNearbyEnemiesOnRestore(
        maxProximity: Int = 2,
        separationDistance: Int = 4
    ) -> Int {
        guard let player = playerPosition else { return 0 }

        let nearbyIDs = entities.compactMap { entity -> UUID? in
            guard entity.isEnemy, entity.position.story == player.story else { return nil }
            return manhattanDistance(entity.position, player) <= maxProximity ? entity.id : nil
        }
        guard !nearbyIDs.isEmpty else { return 0 }

        var occupied = Set(entities.map(\.position))
        var moved = 0

        for id in nearbyIDs {
            guard let enemy = entity(id: id) else { continue }
            occupied.remove(enemy.position)
            guard let destination = restoreSeparationDestination(
                from: player,
                distance: separationDistance,
                occupied: occupied
            ) else {
                occupied.insert(enemy.position)
                continue
            }
            setEntityPosition(destination, id: id)
            occupied.insert(destination)
            moved += 1
        }
        return moved
    }

    mutating func resolvePit(at coord: GridCoord) -> PitResolution {
        guard tile(at: coord)?.isPit == true else { return .none }
        // Stay on the pit tile; UI relocates after the pit screen is dismissed.
        return .hazard
    }

    private func isNonPitFloor(at coord: GridCoord) -> Bool {
        guard let tile = tile(at: coord) else { return false }
        if case .floor(let isPit) = tile.kind { return !isPit }
        return false
    }

    private func manhattanDistance(_ a: GridCoord, _ b: GridCoord) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    /// Prefers a non-pit floor exactly `distance` away (cardinals first), then any farther tile.
    private func restoreSeparationDestination(
        from player: GridCoord,
        distance: Int,
        occupied: Set<GridCoord>
    ) -> GridCoord? {
        let exactRing = coordinatesAtManhattanDistance(from: player, distance: distance)
            .sorted { lhs, rhs in
                let lhsCardinal = lhs.x == player.x || lhs.y == player.y
                let rhsCardinal = rhs.x == player.x || rhs.y == player.y
                if lhsCardinal != rhsCardinal { return lhsCardinal && !rhsCardinal }
                if lhs.y != rhs.y { return lhs.y < rhs.y }
                return lhs.x < rhs.x
            }

        for coord in exactRing {
            if isFreeRestoreTile(coord, occupied: occupied) { return coord }
        }

        // Fallback: nearest free non-pit floor at least `distance` away.
        var queue = [player]
        var visited: Set<GridCoord> = [player]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard next.story == player.story, isInBounds(next), !visited.contains(next) else {
                    continue
                }
                visited.insert(next)
                queue.append(next)
                guard manhattanDistance(next, player) >= distance else { continue }
                if isFreeRestoreTile(next, occupied: occupied) { return next }
            }
        }
        return nil
    }

    private func coordinatesAtManhattanDistance(from origin: GridCoord, distance: Int) -> [GridCoord] {
        guard distance > 0 else { return [origin] }
        var coords: [GridCoord] = []
        for dx in -distance...distance {
            let remaining = distance - abs(dx)
            if remaining == 0 {
                coords.append(origin.neighbor(dx: dx, dy: 0))
            } else {
                coords.append(origin.neighbor(dx: dx, dy: remaining))
                coords.append(origin.neighbor(dx: dx, dy: -remaining))
            }
        }
        return coords
    }

    private func isFreeRestoreTile(_ coord: GridCoord, occupied: Set<GridCoord>) -> Bool {
        isNonPitFloor(at: coord) && !occupied.contains(coord)
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
        case .wall(let destructible):
            return "W\(destructible ? "d" : "")"
        case .gate:
            return "G"
        }
    }
}

nonisolated enum PitResolution: Equatable, Sendable {
    case none
    case hazard
}
