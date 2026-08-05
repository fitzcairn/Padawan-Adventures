import Foundation

nonisolated extension ProceduralGenerator {
    // MARK: - Packed adjacency joins

    /// Gate-ready 2-cell wall segments grouped by the room pair they separate.
    func sharedWallSegmentsByPair(
        in story: [[Tile]],
        roomByCell: [GridCoord: Int]
    ) -> [RoomPair: [[GridCoord]]] {
        var result: [RoomPair: [[GridCoord]]] = [:]
        for segment in partitionGateSegments(in: story, roomByCell: roomByCell) {
            guard let first = segment.first,
                  let info = roomPartitionInfo(first, roomByCell: roomByCell)
            else { continue }
            guard isSealedPathSegment(segment, in: story, roomByCell: roomByCell) else { continue }
            guard segmentHasSolidWallFlanks(
                segment,
                alongDX: info.alongDX,
                alongDY: info.alongDY,
                in: story
            ) else { continue }
            result[info.pair, default: []].append(segment)
        }
        return result
    }

    /// Prim spanning tree restricted to room pairs that share a gate-ready wall.
    func adjacencySpanningTree(
        rooms: [GeneratedRoom],
        segmentsByPair: [RoomPair: [[GridCoord]]]
    ) -> [(Int, Int)] {
        guard rooms.count > 1 else { return [] }

        var inTree = Set([0])
        var edges: [(Int, Int)] = []

        while inTree.count < rooms.count {
            var best: (Int, Int, Int)?
            for i in inTree {
                for j in 0..<rooms.count where !inTree.contains(j) {
                    guard segmentsByPair[RoomPair(i, j)] != nil else { continue }
                    let dist = manhattan(rooms[i].center, rooms[j].center)
                    if best == nil || dist < best!.2 || (dist == best!.2 && (i, j) < (best!.0, best!.1)) {
                        best = (i, j, dist)
                    }
                }
            }
            guard let edge = best else { break }
            inTree.insert(edge.1)
            edges.append((edge.0, edge.1))
        }

        return edges
    }

    /// Writes one 2-cell join into the shared wall of each edge: a gated strip on hit,
    /// or a carved floor doorway on miss. No further carving.
    @discardableResult
    func placeJoinGates(
        _ edges: [(Int, Int)],
        segmentsByPair: [RoomPair: [[GridCoord]]],
        tiles: inout [[[Tile]]],
        story: Int,
        gateMinigames: [WeightedGateKind],
        gateProbability: Double,
        doorwayCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> Int {
        let ordered = edges.sorted { lhs, rhs in
            let a = (min(lhs.0, lhs.1), max(lhs.0, lhs.1))
            let b = (min(rhs.0, rhs.1), max(rhs.0, rhs.1))
            return a < b
        }
        var placed = 0
        for (aIndex, bIndex) in ordered {
            let pair = RoomPair(aIndex, bIndex)
            guard let segments = segmentsByPair[pair], !segments.isEmpty else { continue }
            let mid = segments.count / 2
            var chosen: [GridCoord]?
            for offset in 0..<segments.count {
                let left = mid - offset
                let right = mid + offset
                let candidates = [left, right].filter { $0 >= 0 && $0 < segments.count }
                // Prefer the middle-most unique index first, then its mirror.
                var tried = Set<Int>()
                for idx in candidates where tried.insert(idx).inserted {
                    let segment = segments[idx]
                    guard !segmentAbutsGate(segment, in: tiles[story]) else { continue }
                    chosen = segment
                    break
                }
                if chosen != nil { break }
            }
            guard let segment = chosen else { continue }
            if rng.nextBool(probability: gateProbability) {
                let kind = pickGateMinigameKind(from: gateMinigames, rng: &rng)
                for cell in segment {
                    tiles[story][cell.y][cell.x] = Tile(kind: .gate(minigame: kind))
                }
            } else {
                for cell in segment {
                    tiles[story][cell.y][cell.x] = Tile(kind: .floor(isPit: false))
                    doorwayCells.insert(cell)
                }
            }
            placed += 1
        }
        return placed
    }

    // MARK: - Reachability repair

    /// Opens an unused shared wall (gate or doorway) when a room is not yet reachable.
    @discardableResult
    func ensureGateConnectivity(
        rooms: [GeneratedRoom],
        spawn: GridCoord,
        segmentsByPair: [RoomPair: [[GridCoord]]],
        tiles: inout [[[Tile]]],
        story: Int,
        gateMinigames: [WeightedGateKind],
        gateProbability: Double,
        doorwayCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> Int {
        var placed = 0
        let ordered = rooms.sorted(by: { $0.id < $1.id })
        for _ in 0..<rooms.count {
            var repaired = false
            for room in ordered {
                guard !roomReachable(room, from: spawn, tiles: tiles, story: story) else { continue }
                // Prefer a segment toward any already-reachable room.
                let candidates = segmentsByPair.keys
                    .filter { $0.low == room.id || $0.high == room.id }
                    .sorted { ($0.low, $0.high) < ($1.low, $1.high) }
                for pair in candidates {
                    let otherID = pair.low == room.id ? pair.high : pair.low
                    guard let other = rooms.first(where: { $0.id == otherID }) else { continue }
                    guard roomReachable(other, from: spawn, tiles: tiles, story: story) else { continue }
                    let edge = (min(room.id, otherID), max(room.id, otherID))
                    let count = placeJoinGates(
                        [edge],
                        segmentsByPair: segmentsByPair,
                        tiles: &tiles,
                        story: story,
                        gateMinigames: gateMinigames,
                        gateProbability: gateProbability,
                        doorwayCells: &doorwayCells,
                        rng: &rng
                    )
                    if count > 0 {
                        placed += count
                        repaired = true
                        break
                    }
                }
                if repaired { break }
            }
            if !repaired { break }
        }
        return placed
    }

    func roomReachable(
        _ room: GeneratedRoom,
        from spawn: GridCoord,
        tiles: [[[Tile]]],
        story: Int
    ) -> Bool {
        let reachable = reachableCells(from: spawn, tiles: tiles, story: story)
        return room.cells.contains(where: { reachable.contains($0) })
    }

    func reachableCells(from start: GridCoord, tiles: [[[Tile]]], story: Int) -> Set<GridCoord> {
        var queue = [start]
        var visited = Set<GridCoord>([start])

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard next.story == story else { continue }
                guard next.y >= 0, next.y < tiles[story].count else { continue }
                guard next.x >= 0, next.x < tiles[story][next.y].count else { continue }
                guard !visited.contains(next) else { continue }
                guard isGenerationPassable(tiles[story][next.y][next.x]) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return visited
    }

    // MARK: - Pits / walls / gates

    /// Places exactly one 2-tile gate so `RequiredInteractable.gate` stays satisfiable.
    /// Prefers a sealed shared-wall segment; falls back to re-gating an open doorway.
    @discardableResult
    func forceOneGate(
        rooms: [GeneratedRoom],
        in story: inout [[Tile]],
        gateMinigames: [WeightedGateKind],
        doorways: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> Bool {
        let roomByCell: [GridCoord: Int] = rooms.reduce(into: [:]) { map, room in
            for cell in room.cells {
                map[cell] = room.id
            }
        }
        let occupiedPairs = roomPairsSeparatedByGate(in: story, roomByCell: roomByCell)

        for segment in partitionGateSegments(in: story, roomByCell: roomByCell) {
            guard segment.count == 2 else { continue }
            guard let first = segment.first,
                  let info = roomPartitionInfo(first, roomByCell: roomByCell),
                  !occupiedPairs.contains(info.pair)
            else { continue }
            guard !segmentAbutsGate(segment, in: story) else { continue }
            guard isSealedPathSegment(segment, in: story, roomByCell: roomByCell) else { continue }
            guard segmentHasSolidWallFlanks(
                segment,
                alongDX: info.alongDX,
                alongDY: info.alongDY,
                in: story
            ) else { continue }

            let kind = pickGateMinigameKind(from: gateMinigames, rng: &rng)
            for cell in segment {
                story[cell.y][cell.x] = Tile(kind: .gate(minigame: kind))
            }
            return true
        }

        // Fallback: no sealed segment left, so re-gate a doorway we opened.
        let ordered = doorways.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        for cell in ordered {
            let partner = GridCoord.cardinals.lazy
                .map { cell.neighbor(dx: $0.dx, dy: $0.dy) }
                .first(where: { doorways.contains($0) })
            guard let partner else { continue }
            let kind = pickGateMinigameKind(from: gateMinigames, rng: &rng)
            for target in [cell, partner] {
                story[target.y][target.x] = Tile(kind: .gate(minigame: kind))
                doorways.remove(target)
            }
            return true
        }
        return false
    }

    func pickGateMinigameKind(
        from minigames: [WeightedGateKind],
        rng: inout SeededGenerator
    ) -> GateMinigameKind {
        let pool = minigames.isEmpty
            ? [WeightedGateKind(kind: .soundOutWord, weight: 1)]
            : minigames
        let picked = WeightedPicker.pick(from: pool, weight: \.weight, using: &rng)
        return (picked ?? pool[0]).kind
    }

    /// True when the cells immediately before/after the segment along the wall are solid walls.
    func segmentHasSolidWallFlanks(
        _ segment: [GridCoord],
        alongDX: Int,
        alongDY: Int,
        in story: [[Tile]]
    ) -> Bool {
        let ordered = segment.sorted { lhs, rhs in
            let lhsKey = lhs.x * alongDX + lhs.y * alongDY
            let rhsKey = rhs.x * alongDX + rhs.y * alongDY
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            return lhs.y < rhs.y
        }
        guard let first = ordered.first, let last = ordered.last else { return false }
        let before = first.neighbor(dx: -alongDX, dy: -alongDY)
        let after = last.neighbor(dx: alongDX, dy: alongDY)
        return isSolidWall(before, in: story)
            && isSolidWall(after, in: story)
    }

    func isSolidWall(_ coord: GridCoord, in story: [[Tile]]) -> Bool {
        guard coord.y >= 0, coord.y < story.count else { return false }
        guard coord.x >= 0, coord.x < story[coord.y].count else { return false }
        if case .wall = story[coord.y][coord.x].kind { return true }
        return false
    }

    /// Room pairs that already have a gate on their join (shared-wall partition).
    func roomPairsSeparatedByGate(
        in story: [[Tile]],
        roomByCell: [GridCoord: Int]
    ) -> Set<RoomPair> {
        var pairs = Set<RoomPair>()
        var visitedGates = Set<GridCoord>()

        for y in 0..<story.count {
            for x in 0..<story[y].count {
                let start = GridCoord(x: x, y: y, story: 0)
                guard story[y][x].isGate else { continue }
                guard visitedGates.insert(start).inserted else { continue }

                // Contiguous gate feature (one puzzle strip).
                var component = [start]
                var head = 0
                while head < component.count {
                    let current = component[head]
                    head += 1
                    for (dx, dy) in GridCoord.cardinals {
                        let next = current.neighbor(dx: dx, dy: dy)
                        guard next.y >= 0, next.y < story.count else { continue }
                        guard next.x >= 0, next.x < story[next.y].count else { continue }
                        guard story[next.y][next.x].isGate else { continue }
                        guard visitedGates.insert(next).inserted else { continue }
                        component.append(next)
                    }
                }

                // Classic shared-wall: rooms on opposite sides of a gate cell.
                for coord in component {
                    for (dx, dy) in GridCoord.cardinals {
                        let a = coord.neighbor(dx: dx, dy: dy)
                        let b = coord.neighbor(dx: -dx, dy: -dy)
                        guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
                        pairs.insert(RoomPair(idA, idB))
                    }
                }

                // Corridor-mouth: flood hallway floors from this strip (other gates block)
                // and collect every room that touches the pocket — typically the two joined rooms.
                var rooms = Set<Int>()
                var flood = component
                var flooded = Set(component)
                var floodHead = 0
                while floodHead < flood.count {
                    let current = flood[floodHead]
                    floodHead += 1
                    for (dx, dy) in GridCoord.cardinals {
                        let next = current.neighbor(dx: dx, dy: dy)
                        if let roomID = roomByCell[next] {
                            rooms.insert(roomID)
                            continue
                        }
                        guard next.y >= 0, next.y < story.count else { continue }
                        guard next.x >= 0, next.x < story[next.y].count else { continue }
                        guard flooded.insert(next).inserted else { continue }
                        guard isFloor(story[next.y][next.x]) else { continue }
                        flood.append(next)
                    }
                }
                let orderedRooms = rooms.sorted()
                if orderedRooms.count == 2 {
                    pairs.insert(RoomPair(orderedRooms[0], orderedRooms[1]))
                }
            }
        }
        return pairs
    }

    func segmentAbutsGate(_ segment: [GridCoord], in story: [[Tile]]) -> Bool {
        abuttingGateKind(segment, in: story) != nil
    }

    func abuttingGateKind(_ segment: [GridCoord], in story: [[Tile]]) -> GateMinigameKind? {
        for cell in segment {
            for (dx, dy) in GridCoord.cardinals {
                let next = cell.neighbor(dx: dx, dy: dy)
                guard next.y >= 0, next.y < story.count else { continue }
                guard next.x >= 0, next.x < story[next.y].count else { continue }
                if let kind = story[next.y][next.x].gateMinigame { return kind }
            }
        }
        return nil
    }

    /// True when every cell is a solid wall between the same room pair (sealed shortcut).
    func isSealedPathSegment(
        _ segment: [GridCoord],
        in story: [[Tile]],
        roomByCell: [GridCoord: Int]
    ) -> Bool {
        guard let first = segment.first,
              let info = roomPartitionInfo(first, roomByCell: roomByCell)
        else { return false }

        for cell in segment {
            guard case .wall = story[cell.y][cell.x].kind else { return false }
            guard let cellInfo = roomPartitionInfo(cell, roomByCell: roomByCell),
                  cellInfo.pair == info.pair
            else { return false }
        }
        return true
    }

    /// Candidate 2-tile solid-wall segments between distinct rooms (no singles / corners).
    func partitionGateSegments(
        in story: [[Tile]],
        roomByCell: [GridCoord: Int]
    ) -> [[GridCoord]] {
        var partitionCells: [(GridCoord, RoomPair, Int, Int)] = []
        for y in 0..<story.count {
            for x in 0..<story[y].count {
                guard case .wall = story[y][x].kind else { continue }
                let coord = GridCoord(x: x, y: y, story: 0)
                guard let (pair, alongDX, alongDY) = roomPartitionInfo(coord, roomByCell: roomByCell)
                else { continue }
                partitionCells.append((coord, pair, alongDX, alongDY))
            }
        }

        partitionCells.sort { lhs, rhs in
            if lhs.0.x != rhs.0.x { return lhs.0.x < rhs.0.x }
            return lhs.0.y < rhs.0.y
        }

        var segments: [[GridCoord]] = []
        var used = Set<GridCoord>()
        for (coord, pair, alongDX, alongDY) in partitionCells {
            guard !used.contains(coord) else { continue }

            let next = coord.neighbor(dx: alongDX, dy: alongDY)
            if let nextInfo = roomPartitionInfo(next, roomByCell: roomByCell),
               nextInfo.pair == pair,
               case .wall = story[next.y][next.x].kind,
               !used.contains(next) {
                let segment = [coord, next].sorted { ($0.x, $0.y) < ($1.x, $1.y) }
                segments.append(segment)
                used.formUnion(segment)
                continue
            }

            let prev = coord.neighbor(dx: -alongDX, dy: -alongDY)
            if let prevInfo = roomPartitionInfo(prev, roomByCell: roomByCell),
               prevInfo.pair == pair,
               case .wall = story[prev.y][prev.x].kind,
               !used.contains(prev) {
                let segment = [prev, coord].sorted { ($0.x, $0.y) < ($1.x, $1.y) }
                segments.append(segment)
                used.formUnion(segment)
                continue
            }
            // Single partition cells / corners are not valid partition gates.
        }

        return segments.sorted { lhs, rhs in
            let a = lhs[0]
            let b = rhs[0]
            if a.x != b.x { return a.x < b.x }
            return a.y < b.y
        }
    }

    func roomPartitionInfo(
        _ coord: GridCoord,
        roomByCell: [GridCoord: Int]
    ) -> (pair: RoomPair, alongDX: Int, alongDY: Int)? {
        for (dx, dy) in GridCoord.cardinals {
            let a = coord.neighbor(dx: dx, dy: dy)
            let b = coord.neighbor(dx: -dx, dy: -dy)
            guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
            // Along-wall axis is perpendicular to the room-to-room step.
            return (RoomPair(idA, idB), -dy, dx)
        }
        return nil
    }

    // MARK: - Helpers

    func manhattan(_ a: GridCoord, _ b: GridCoord) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    func isFloor(_ tile: Tile) -> Bool {
        if case .floor = tile.kind { return true }
        return false
    }

    /// Generation reachability treats gates as passable (walls block).
    func isGenerationPassable(_ tile: Tile) -> Bool {
        switch tile.kind {
        case .floor(_), .gate(_):
            return true
        case .wall:
            return false
        }
    }

    func runGatesPass(state: inout GenerationAttemptState, config: WorldGenerationConfig) {
        let params = config.generation
        let roomByCell: [GridCoord: Int] = state.rooms.reduce(into: [:]) { map, room in
            for cell in room.cells {
                map[cell] = room.id
            }
        }
        let segmentsByPair = sharedWallSegmentsByPair(in: state.tiles[0], roomByCell: roomByCell)
        state.joinEdges = adjacencySpanningTree(rooms: state.rooms, segmentsByPair: segmentsByPair)
        state.topRight = topRightRoom(from: state.rooms)
        state.spawn = spawnCell(for: state.topRight)

        placeJoinGates(
            state.joinEdges,
            segmentsByPair: segmentsByPair,
            tiles: &state.tiles,
            story: 0,
            gateMinigames: config.gateMinigames,
            gateProbability: params.room.gateProbability,
            doorwayCells: &state.doorwayCells,
            rng: &state.rng
        )
        ensureGateConnectivity(
            rooms: state.rooms,
            spawn: state.spawn,
            segmentsByPair: segmentsByPair,
            tiles: &state.tiles,
            story: 0,
            gateMinigames: config.gateMinigames,
            gateProbability: params.room.gateProbability,
            doorwayCells: &state.doorwayCells,
            rng: &state.rng
        )
    }
}
