import Foundation

struct GeneratedRoom: Equatable, Sendable {
    let id: Int
    let cells: Set<GridCoord>
    let center: GridCoord
}

struct GenerationResult: Sendable {
    let world: GameWorld
    let rooms: [GeneratedRoom]
    let topRightRoomID: Int
    let joinPairs: [(Int, Int)]
}

struct ProceduralGenerator: Sendable {
    func generate(from config: WorldSeedConfig) throws -> GameWorld {
        try generateDetailed(from: config).world
    }

    func generateDetailed(from config: WorldSeedConfig) throws -> GenerationResult {
        try config.validate()

        var rng = SeededGenerator(seed: config.seed)
        let width = config.world.width
        let height = config.world.height
        let stories = config.world.stories
        let params = config.generation

        var tiles = filledWalls(width: width, height: height, stories: stories)

        let rooms = placeRooms(
            count: params.roomCount,
            minSize: params.minRoomSize,
            maxSize: params.maxRoomSize,
            width: width,
            height: height,
            rng: &rng
        )

        carveRooms(rooms, into: &tiles[0])

        let mstEdges = minimumSpanningTree(for: rooms)
        joinRooms(rooms: rooms, edges: mstEdges, tiles: &tiles, story: 0)

        let topRight = topRightRoom(from: rooms)
        var spawn = spawnCell(for: topRight)
        ensureReachability(rooms: rooms, spawn: spawn, tiles: &tiles, story: 0)

        sprinklePits(into: &tiles[0], chance: params.pitChance, excluding: spawn, rng: &rng)
        clearPits(around: spawn, tiles: &tiles, story: 0)
        markDestructibleWalls(in: &tiles[0], chance: params.wallDestructibleChance, rng: &rng)

        placeLadders(in: &tiles, count: params.ladderCount, rng: &rng)
        placeRamps(in: &tiles, count: params.rampCount, rng: &rng)
        placeSlides(in: &tiles, count: params.slideCount, rng: &rng)

        let letter = config.player.letter.first ?? "P"
        let player = GameEntity(letter: letter, position: spawn, isPlayer: true)

        let world = GameWorld(
            width: width,
            height: height,
            storyCount: stories,
            tiles: tiles,
            entities: [player],
            spawn: spawn
        )

        return GenerationResult(
            world: world,
            rooms: rooms,
            topRightRoomID: topRight.id,
            joinPairs: mstEdges
        )
    }

    // MARK: - Room placement

    private func filledWalls(width: Int, height: Int, stories: Int) -> [[[Tile]]] {
        Array(
            repeating: Array(
                repeating: Array(
                    repeating: Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
                    count: width
                ),
                count: height
            ),
            count: stories
        )
    }

    private func placeRooms(
        count: Int,
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> [GeneratedRoom] {
        var rooms: [GeneratedRoom] = []
        var occupied = Set<GridCoord>()
        let maxAttempts = count * 80

        for attempt in 0..<maxAttempts where rooms.count < count {
            let cells: Set<GridCoord>
            if rng.nextBool(probability: 0.7) {
                cells = makeRectRoom(minSize: minSize, maxSize: maxSize, width: width, height: height, rng: &rng)
            } else {
                cells = makeLShapeRoom(minSize: minSize, maxSize: maxSize, width: width, height: height, rng: &rng)
            }

            guard !cells.isEmpty else { continue }

            let buffered = buffer(cells: cells, width: width, height: height, padding: 1)
            if !buffered.isDisjoint(with: occupied) { continue }

            occupied.formUnion(buffered)
            let center = centroid(of: cells)
            rooms.append(GeneratedRoom(id: rooms.count, cells: cells, center: center))
        }

        return rooms
    }

    private func makeRectRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let w = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let h = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        guard width > w + 2, height > h + 2 else { return [] }

        let x = rng.nextInt(upperBound: width - w - 1) + 1
        let y = rng.nextInt(upperBound: height - h - 1) + 1

        var cells = Set<GridCoord>()
        for row in y..<(y + h) {
            for col in x..<(x + w) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }
        return cells
    }

    private func makeLShapeRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let mainW = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let mainH = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let extW = rng.nextInt(upperBound: max(1, maxSize - minSize)) + minSize
        let extH = rng.nextInt(upperBound: max(1, maxSize - minSize)) + minSize

        guard width > mainW + extW + 2, height > mainH + extH + 2 else { return [] }

        let x = rng.nextInt(upperBound: width - mainW - extW - 1) + 1
        let y = rng.nextInt(upperBound: height - mainH - extH - 1) + 1

        var cells = Set<GridCoord>()
        for row in y..<(y + mainH) {
            for col in x..<(x + mainW) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }

        let attachRight = rng.nextBool(probability: 0.5)
        if attachRight {
            let extX = x + mainW - 1
            let extY = y + mainH - 1
            for row in extY..<min(height - 1, extY + extH) {
                for col in extX..<min(width - 1, extX + extW) {
                    cells.insert(GridCoord(x: col, y: row, story: 0))
                }
            }
        } else {
            let extX = x + mainW - 1
            let extY = y
            for row in extY..<min(height - 1, extY + extH) {
                for col in extX..<min(width - 1, extX + extW) {
                    cells.insert(GridCoord(x: col, y: row, story: 0))
                }
            }
        }

        return cells
    }

    private func buffer(cells: Set<GridCoord>, width: Int, height: Int, padding: Int) -> Set<GridCoord> {
        var expanded = Set<GridCoord>()
        for cell in cells {
            for dy in -padding...padding {
                for dx in -padding...padding {
                    let c = GridCoord(x: cell.x + dx, y: cell.y + dy, story: 0)
                    guard c.x >= 0, c.x < width, c.y >= 0, c.y < height else { continue }
                    expanded.insert(c)
                }
            }
        }
        return expanded
    }

    private func centroid(of cells: Set<GridCoord>) -> GridCoord {
        let sum = cells.reduce((x: 0, y: 0)) { partial, cell in
            (partial.x + cell.x, partial.y + cell.y)
        }
        let count = max(cells.count, 1)
        return GridCoord(x: sum.x / count, y: sum.y / count, story: 0)
    }

    private func spawnCell(for room: GeneratedRoom) -> GridCoord {
        guard let nearest = room.cells.min(by: { a, b in
            let da = abs(a.x - room.center.x) + abs(a.y - room.center.y)
            let db = abs(b.x - room.center.x) + abs(b.y - room.center.y)
            return da < db
        }) else {
            return room.center
        }
        return nearest
    }

    private func carveRooms(_ rooms: [GeneratedRoom], into story: inout [[Tile]]) {
        for room in rooms {
            for cell in room.cells {
                story[cell.y][cell.x] = Tile(kind: .floor(isPit: false))
            }
        }
    }

    // MARK: - MST + door joins

    private func minimumSpanningTree(for rooms: [GeneratedRoom]) -> [(Int, Int)] {
        guard rooms.count > 1 else { return [] }

        var inTree = Set([0])
        var edges: [(Int, Int)] = []

        while inTree.count < rooms.count {
            var best: (Int, Int, Int)?
            for i in inTree {
                for j in 0..<rooms.count where !inTree.contains(j) {
                    let dist = manhattan(rooms[i].center, rooms[j].center)
                    if best == nil || dist < best!.2 {
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

    private func joinRooms(
        rooms: [GeneratedRoom],
        edges: [(Int, Int)],
        tiles: inout [[[Tile]]],
        story: Int
    ) {
        for (aIndex, bIndex) in edges {
            joinPair(rooms[aIndex], rooms[bIndex], tiles: &tiles, story: story)
        }
    }

    private func joinPair(
        _ roomA: GeneratedRoom,
        _ roomB: GeneratedRoom,
        tiles: inout [[[Tile]]],
        story: Int
    ) {
        let (start, end) = closestPair(roomA, roomB)
        let path = lPath(from: start, to: end)

        for index in 1..<path.count {
            let previous = path[index - 1]
            let current = path[index]

            if roomB.cells.contains(current), !roomB.cells.contains(previous) {
                setDoor(at: previous, tiles: &tiles, story: story)
                continue
            }
            if roomA.cells.contains(current), !roomA.cells.contains(previous) {
                setDoor(at: previous, tiles: &tiles, story: story)
                continue
            }
            if roomA.cells.contains(previous), !roomA.cells.contains(current) {
                setDoor(at: current, tiles: &tiles, story: story)
                continue
            }
            if roomB.cells.contains(previous), !roomB.cells.contains(current) {
                setDoor(at: current, tiles: &tiles, story: story)
                continue
            }
            if !roomA.cells.contains(current), !roomB.cells.contains(current) {
                tiles[story][current.y][current.x] = Tile(kind: .floor(isPit: false))
            }
        }

        placeDoorOnBoundary(room: roomA, tiles: &tiles, story: story)
        placeDoorOnBoundary(room: roomB, tiles: &tiles, story: story)
    }

    private func setDoor(at coord: GridCoord, tiles: inout [[[Tile]]], story: Int) {
        guard coord.y >= 0, coord.y < tiles[story].count else { return }
        guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { return }

        switch tiles[story][coord.y][coord.x].kind {
        case .wall(let destructible, _, let hasLadder):
            tiles[story][coord.y][coord.x] = Tile(kind: .wall(destructible: destructible, hasDoor: true, hasLadder: hasLadder))
        case .floor:
            tiles[story][coord.y][coord.x] = Tile(kind: .wall(destructible: false, hasDoor: true, hasLadder: false))
        default:
            break
        }
    }

    private func closestPair(_ roomA: GeneratedRoom, _ roomB: GeneratedRoom) -> (GridCoord, GridCoord) {
        var bestA = roomA.center
        var bestB = roomB.center
        var bestDist = Int.max

        let cellsA = roomA.cells.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        let cellsB = roomB.cells.sorted { ($0.x, $0.y) < ($1.x, $1.y) }

        for a in cellsA {
            for b in cellsB {
                let dist = manhattan(a, b)
                if dist < bestDist {
                    bestDist = dist
                    bestA = a
                    bestB = b
                }
            }
        }
        return (bestA, bestB)
    }

    private func lPath(from start: GridCoord, to end: GridCoord) -> [GridCoord] {
        var path = [start]
        var x = start.x
        var y = start.y

        while x != end.x {
            x += x < end.x ? 1 : -1
            path.append(GridCoord(x: x, y: y, story: start.story))
        }
        while y != end.y {
            y += y < end.y ? 1 : -1
            path.append(GridCoord(x: x, y: y, story: start.story))
        }
        return path
    }

    private func placeDoorOnBoundary(
        room: GeneratedRoom,
        tiles: inout [[[Tile]]],
        story: Int
    ) {
        let cells = room.cells.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        for cell in cells {
            let neighbors = GridCoord.cardinals.map { cell.neighbor(dx: $0.dx, dy: $0.dy) }
                .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            for neighbor in neighbors {
                guard !room.cells.contains(neighbor) else { continue }
                guard isFloor(tiles[story][neighbor.y][neighbor.x]) || isDoor(tiles[story][neighbor.y][neighbor.x]) else { continue }

                let wallCandidates = GridCoord.cardinals
                    .map { cell.neighbor(dx: $0.dx, dy: $0.dy) }
                    .filter { !room.cells.contains($0) }
                    .sorted { ($0.x, $0.y) < ($1.x, $1.y) }

                for wallCell in wallCandidates {
                    if case .wall(let destructible, false, let hasLadder) = tiles[story][wallCell.y][wallCell.x].kind {
                        tiles[story][wallCell.y][wallCell.x] = Tile(
                            kind: .wall(destructible: destructible, hasDoor: true, hasLadder: hasLadder)
                        )
                        return
                    }
                }
            }
        }
    }

    private func topRightRoom(from rooms: [GeneratedRoom]) -> GeneratedRoom {
        rooms.max { lhs, rhs in
            let lhsScore = (lhs.center.x - lhs.center.y, -(lhs.center.x + lhs.center.y))
            let rhsScore = (rhs.center.x - rhs.center.y, -(rhs.center.x + rhs.center.y))
            return lhsScore < rhsScore
        } ?? rooms[0]
    }

    // MARK: - Reachability repair

    private func ensureReachability(
        rooms: [GeneratedRoom],
        spawn: GridCoord,
        tiles: inout [[[Tile]]],
        story: Int
    ) {
        for room in rooms.sorted(by: { $0.id < $1.id }) {
            guard !roomReachable(room, from: spawn, tiles: tiles, story: story) else { continue }
            if let other = rooms.sorted(by: { $0.id < $1.id }).first(where: { roomReachable($0, from: spawn, tiles: tiles, story: story) }) {
                joinPair(other, room, tiles: &tiles, story: story)
            }
        }
    }

    private func roomReachable(
        _ room: GeneratedRoom,
        from spawn: GridCoord,
        tiles: [[[Tile]]],
        story: Int
    ) -> Bool {
        let reachable = reachableCells(from: spawn, tiles: tiles, story: story)
        return room.cells.contains(where: { reachable.contains($0) })
    }

    private func reachableCells(from start: GridCoord, tiles: [[[Tile]]], story: Int) -> Set<GridCoord> {
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
                guard isEnterable(tiles[story][next.y][next.x]) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return visited
    }

    // MARK: - Pits / walls / vertical features

    private func sprinklePits(
        into story: inout [[Tile]],
        chance: Double,
        excluding spawn: GridCoord,
        rng: inout SeededGenerator
    ) {
        for y in 0..<story.count {
            for x in 0..<story[y].count {
                let coord = GridCoord(x: x, y: y, story: 0)
                if coord == spawn { continue }
                if case .floor = story[y][x].kind, rng.nextBool(probability: chance) {
                    story[y][x] = Tile(kind: .floor(isPit: true))
                }
            }
        }
    }

    private func clearPits(around spawn: GridCoord, tiles: inout [[[Tile]]], story: Int) {
        var coords = [spawn]
        for (dx, dy) in GridCoord.cardinals {
            coords.append(spawn.neighbor(dx: dx, dy: dy))
        }
        for coord in coords {
            guard coord.y >= 0, coord.y < tiles[story].count else { continue }
            guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { continue }
            if case .floor = tiles[story][coord.y][coord.x].kind {
                tiles[story][coord.y][coord.x] = Tile(kind: .floor(isPit: false))
            }
        }
    }

    private func markDestructibleWalls(
        in story: inout [[Tile]],
        chance: Double,
        rng: inout SeededGenerator
    ) {
        for y in 0..<story.count {
            for x in 0..<story[y].count {
                if case .wall(false, false, false) = story[y][x].kind,
                   rng.nextBool(probability: chance) {
                    story[y][x] = Tile(kind: .wall(destructible: true, hasDoor: false, hasLadder: false))
                }
            }
        }
    }

    private func placeLadders(in tiles: inout [[[Tile]]], count: Int, rng: inout SeededGenerator) {
        var placed = 0
        var attempts = 0
        while placed < count, attempts < count * 50 {
            attempts += 1
            let x = rng.nextInt(upperBound: tiles[0][0].count)
            let y = rng.nextInt(upperBound: tiles[0].count)

            for story in 0..<(tiles.count - 1) {
                guard case .wall(let destructible, let door, false) = tiles[story][y][x].kind else { continue }
                guard case .wall = tiles[story + 1][y][x].kind else { continue }
                guard adjacentFloorCount(at: GridCoord(x: x, y: y, story: story), tiles: tiles) >= 1 else { continue }

                tiles[story][y][x] = Tile(kind: .wall(destructible: destructible, hasDoor: door, hasLadder: true))
                tiles[story + 1][y][x] = Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true))
                placed += 1
                break
            }
        }
    }

    private func placeRamps(in tiles: inout [[[Tile]]], count: Int, rng: inout SeededGenerator) {
        var placed = 0
        var attempts = 0
        while placed < count, attempts < count * 50 {
            attempts += 1
            let lowerStory = 0
            let upperStory = 1
            let horizontal = rng.nextBool(probability: 0.5)
            let x = rng.nextInt(upperBound: tiles[lowerStory][0].count - (horizontal ? 2 : 1))
            let y = rng.nextInt(upperBound: tiles[lowerStory].count - (horizontal ? 1 : 2))

            let a = GridCoord(x: x, y: y, story: lowerStory)
            let b = horizontal
                ? GridCoord(x: x + 1, y: y, story: lowerStory)
                : GridCoord(x: x, y: y + 1, story: lowerStory)

            guard isFloor(tiles[lowerStory][a.y][a.x]), isFloor(tiles[lowerStory][b.y][b.x]) else { continue }
            guard isFloor(tiles[upperStory][a.y][a.x]), isFloor(tiles[upperStory][b.y][b.x]) else { continue }

            tiles[lowerStory][a.y][a.x] = Tile(kind: .ramp(partner: b, otherStory: upperStory))
            tiles[lowerStory][b.y][b.x] = Tile(kind: .ramp(partner: a, otherStory: upperStory))
            placed += 1
        }
    }

    private func placeSlides(in tiles: inout [[[Tile]]], count: Int, rng: inout SeededGenerator) {
        var placed = 0
        var attempts = 0
        let upperStory = 1
        let lowerStory = 0

        while placed < count, attempts < count * 50 {
            attempts += 1
            let horizontal = rng.nextBool(probability: 0.5)
            let x = rng.nextInt(upperBound: tiles[upperStory][0].count - (horizontal ? 2 : 1))
            let y = rng.nextInt(upperBound: tiles[upperStory].count - (horizontal ? 1 : 2))

            let a = GridCoord(x: x, y: y, story: upperStory)
            let b = horizontal
                ? GridCoord(x: x + 1, y: y, story: upperStory)
                : GridCoord(x: x, y: y + 1, story: upperStory)

            guard isFloor(tiles[upperStory][a.y][a.x]), isFloor(tiles[upperStory][b.y][b.x]) else { continue }
            guard isFloor(tiles[lowerStory][a.y][a.x]), isFloor(tiles[lowerStory][b.y][b.x]) else { continue }

            tiles[upperStory][a.y][a.x] = Tile(kind: .slide(partner: b, lowerStory: lowerStory))
            tiles[upperStory][b.y][b.x] = Tile(kind: .slide(partner: a, lowerStory: lowerStory))
            placed += 1
        }
    }

    // MARK: - Helpers

    private func manhattan(_ a: GridCoord, _ b: GridCoord) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func isFloor(_ tile: Tile) -> Bool {
        if case .floor = tile.kind { return true }
        return false
    }

    private func isDoor(_ tile: Tile) -> Bool {
        if case .wall(_, true, _) = tile.kind { return true }
        return false
    }

    private func isEnterable(_ tile: Tile) -> Bool {
        switch tile.kind {
        case .floor, .ramp, .slide:
            return true
        case .wall(_, let hasDoor, let hasLadder):
            return hasDoor || hasLadder
        }
    }

    private func adjacentFloorCount(at coord: GridCoord, tiles: [[[Tile]]]) -> Int {
        var count = 0
        for (dx, dy) in GridCoord.cardinals {
            let neighbor = coord.neighbor(dx: dx, dy: dy)
            guard neighbor.story >= 0, neighbor.story < tiles.count else { continue }
            guard neighbor.y >= 0, neighbor.y < tiles[neighbor.story].count else { continue }
            guard neighbor.x >= 0, neighbor.x < tiles[neighbor.story][neighbor.y].count else { continue }
            if isFloor(tiles[neighbor.story][neighbor.y][neighbor.x]) {
                count += 1
            }
        }
        return count
    }
}
