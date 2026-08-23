import Foundation

/// Places the per-level merchant without consuming `GenerationAttemptState.rng`.
nonisolated enum MerchantSpawner {
    static let npcID = "merchant"
    static let seedSalt: UInt64 = 0x3E2C4A17
    /// Same-room vs 1-hop vs 2-hop vs farther, as powers of 4.
    static let biasWeights = [64, 16, 4, 1]

    static func spawn(
        rooms: [GeneratedRoom],
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        entities: inout [GameEntity],
        joinEdges: [(Int, Int)] = [],
        biasTowardTreasure: Bool = true,
        seed: UInt64
    ) {
        guard entities.contains(where: \.isMerchant) == false else { return }
        var rng = SeededGenerator(seed: seed ^ seedSalt)
        let treasure = entities.first { $0.pickupKind == .treasure }?.position
        guard let cell = pickCell(
            rooms: rooms,
            tiles: tiles,
            occupied: occupied,
            treasure: treasure,
            joinEdges: joinEdges,
            biasTowardTreasure: biasTowardTreasure,
            rng: &rng
        ) else {
            return
        }
        occupied.insert(cell)
        entities.append(
            GameEntity(
                letter: "M",
                position: cell,
                npcID: npcID
            )
        )
    }

    static func pickCell(
        rooms: [GeneratedRoom],
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>,
        treasure: GridCoord?,
        joinEdges: [(Int, Int)],
        biasTowardTreasure: Bool,
        rng: inout SeededGenerator
    ) -> GridCoord? {
        let byRoom = placeableCellsByRoom(rooms: rooms, tiles: tiles, occupied: occupied)
        guard !byRoom.isEmpty else { return nil }

        if biasTowardTreasure,
           let treasure,
           let treasureRoom = rooms.first(where: { $0.cells.contains(treasure) })
        {
            let hops = roomHops(from: treasureRoom.id, joinEdges: joinEdges)
            let ranked = byRoom.sorted { lhs, rhs in lhs.room.id < rhs.room.id }
            let weighted: [(PlaceableRoom, Int)] = ranked.map { entry in
                let distance = hops[entry.room.id] ?? fallbackHops(
                    from: treasureRoom.center,
                    to: entry.room.center
                )
                return (entry, biasWeight(hops: distance))
            }
            if let chosen = pickWeighted(weighted, rng: &rng) {
                return pickCell(in: chosen, rng: &rng)
            }
        }

        var all = byRoom.flatMap(\.cells)
        all.sort(by: Self.cellOrder)
        all.shuffle(using: &rng)
        return all.first
    }

    static func roomHops(from startID: Int, joinEdges: [(Int, Int)]) -> [Int: Int] {
        var adjacency: [Int: [Int]] = [:]
        for (a, b) in joinEdges {
            adjacency[a, default: []].append(b)
            adjacency[b, default: []].append(a)
        }
        for id in adjacency.keys {
            adjacency[id]?.sort()
        }

        var distance: [Int: Int] = [startID: 0]
        var queue = [startID]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            for next in adjacency[current] ?? [] {
                guard distance[next] == nil else { continue }
                distance[next] = (distance[current] ?? 0) + 1
                queue.append(next)
            }
        }
        return distance
    }

    static func biasWeight(hops: Int) -> Int {
        let index = min(max(hops, 0), biasWeights.count - 1)
        return biasWeights[index]
    }

    private struct PlaceableRoom {
        var room: GeneratedRoom
        var cells: [GridCoord]
    }

    private static func placeableCellsByRoom(
        rooms: [GeneratedRoom],
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>
    ) -> [PlaceableRoom] {
        rooms.compactMap { room in
            var corners: [GridCoord] = []
            var floors: [GridCoord] = []
            for cell in room.cells {
                guard isPlaceableFloor(cell, tiles: tiles, occupied: occupied) else { continue }
                floors.append(cell)
                if isRoomCorner(cell, room: room) {
                    corners.append(cell)
                }
            }
            let cells = corners.isEmpty ? floors : corners
            guard !cells.isEmpty else { return nil }
            return PlaceableRoom(room: room, cells: cells.sorted(by: cellOrder))
        }
    }

    private static func pickCell(in room: PlaceableRoom, rng: inout SeededGenerator) -> GridCoord? {
        var cells = room.cells
        cells.shuffle(using: &rng)
        return cells.first
    }

    private static func pickWeighted(
        _ items: [(PlaceableRoom, Int)],
        rng: inout SeededGenerator
    ) -> PlaceableRoom? {
        let total = items.reduce(0) { $0 + max($1.1, 0) }
        guard total > 0 else { return items.first?.0 }
        var ticket = rng.nextInt(upperBound: total)
        for (item, weight) in items {
            let w = max(weight, 0)
            if ticket < w { return item }
            ticket -= w
        }
        return items.last?.0
    }

    private static func fallbackHops(from: GridCoord, to: GridCoord) -> Int {
        let tiles = abs(from.x - to.x) + abs(from.y - to.y)
        return max(1, (tiles + 7) / 8)
    }

    private static func cellOrder(_ lhs: GridCoord, _ rhs: GridCoord) -> Bool {
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.story < rhs.story
    }

    static func isRoomCorner(_ cell: GridCoord, room: GeneratedRoom) -> Bool {
        let outward = GridCoord.cardinals.filter { step in
            !room.cells.contains(cell.neighbor(dx: step.dx, dy: step.dy))
        }
        guard outward.count == 2 else { return false }
        return outward[0].dx * outward[1].dx + outward[0].dy * outward[1].dy == 0
    }

    static func isPlaceableFloor(
        _ cell: GridCoord,
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>
    ) -> Bool {
        guard !occupied.contains(cell) else { return false }
        guard cell.story == 0, cell.story < tiles.count else { return false }
        guard cell.y >= 0, cell.y < tiles[cell.story].count else { return false }
        guard cell.x >= 0, cell.x < tiles[cell.story][cell.y].count else { return false }
        switch tiles[cell.story][cell.y][cell.x].kind {
        case .floor(let isPit):
            return !isPit
        case .gate, .wall:
            return false
        }
    }
}
