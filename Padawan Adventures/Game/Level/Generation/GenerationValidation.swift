import Foundation

nonisolated extension ProceduralGenerator {
    /// True when no two rooms' interiors are reachable from each other treating `.gate` as blocked
    /// (floors/pits passable, walls blocked). This is the gated-passage invariant.
    static func roomsAreSeparatedByGates(rooms: [GeneratedRoom], tiles: [[Tile]]) -> Bool {
        guard rooms.count >= 2 else { return true }
        let roomByCell: [GridCoord: Int] = rooms.reduce(into: [:]) { map, room in
            for cell in room.cells {
                map[cell] = room.id
            }
        }
        for room in rooms {
            var queue = Array(room.cells)
            var visited = Set(room.cells)
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                for (dx, dy) in GridCoord.cardinals {
                    let next = current.neighbor(dx: dx, dy: dy)
                    guard !visited.contains(next) else { continue }
                    guard next.y >= 0, next.y < tiles.count else { continue }
                    guard next.x >= 0, next.x < tiles[next.y].count else { continue }
                    let tile = tiles[next.y][next.x]
                    // Gates block; only ordinary floors (incl. pits) are passable.
                    guard case .floor = tile.kind else { continue }
                    if let otherID = roomByCell[next], otherID != room.id {
                        return false
                    }
                    visited.insert(next)
                    queue.append(next)
                }
            }
        }
        return true
    }

    /// True when every room is reachable from `spawn` with gates passable and walls blocking.
    static func allRoomsGateConnected(
        rooms: [GeneratedRoom],
        spawn: GridCoord,
        tiles: [[Tile]]
    ) -> Bool {
        guard !rooms.isEmpty else { return true }
        var queue = [spawn]
        var visited: Set<GridCoord> = [spawn]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard !visited.contains(next) else { continue }
                guard next.y >= 0, next.y < tiles.count else { continue }
                guard next.x >= 0, next.x < tiles[next.y].count else { continue }
                switch tiles[next.y][next.x].kind {
                case .floor(_), .gate(_):
                    visited.insert(next)
                    queue.append(next)
                case .wall:
                    continue
                }
            }
        }
        return rooms.allSatisfy { room in
            room.cells.contains(where: { visited.contains($0) })
        }
    }

    /// Returns which required interactables are absent from a finished world.
    static func missingRequiredInteractables(in world: GameWorld) -> [RequiredInteractable] {
        missingRequiredInteractables(tiles: world.tiles, entities: world.entities)
    }

    static func missingRequiredInteractables(
        tiles: [[[Tile]]],
        entities: [GameEntity]
    ) -> [RequiredInteractable] {
        var missing: [RequiredInteractable] = []
        var hasGate = false
        var hasPit = false

        for story in tiles {
            for row in story {
                for tile in row {
                    if tile.isGate { hasGate = true }
                    if tile.isPit { hasPit = true }
                }
            }
        }

        if !hasGate { missing.append(.gate) }
        if !hasPit { missing.append(.pit) }
        if !entities.contains(where: \.isEnemy) { missing.append(.enemy) }
        return missing
    }
}
