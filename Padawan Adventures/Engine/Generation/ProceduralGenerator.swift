import Foundation

struct GeneratedRoom: Equatable, Sendable {
    let id: Int
    let cells: Set<GridCoord>
    let center: GridCoord
    /// Lattice coordinates used for packed-room adjacency.
    let latticeX: Int
    let latticeY: Int
}

struct GenerationResult: Sendable {
    let world: GameWorld
    let rooms: [GeneratedRoom]
    let topRightRoomID: Int
    let joinPairs: [(Int, Int)]
}

struct ProceduralGenerator: Sendable {
    func generate(
        from config: WorldSeedConfig,
        enemyConfig: EnemyConfig = .fallback
    ) throws -> GameWorld {
        try generateDetailed(from: config, enemyConfig: enemyConfig).world
    }

    func generateDetailed(
        from config: WorldSeedConfig,
        enemyConfig: EnemyConfig = .fallback
    ) throws -> GenerationResult {
        try config.validate()

        var rng = SeededGenerator(seed: config.seed)
        let width = config.world.width
        let height = config.world.height
        let stories = config.world.stories
        let params = config.generation

        var tiles = filledWalls(width: width, height: height, stories: stories)

        let rooms = placeOrganicRooms(
            count: params.roomCount,
            minSize: params.minRoomSize,
            maxSize: params.maxRoomSize,
            width: width,
            height: height,
            rng: &rng
        )

        carveRooms(rooms, into: &tiles[0])

        let corridorWidth = max(2, params.corridorWidth)

        let mstEdges = geometricMST(for: rooms)
        joinRooms(rooms: rooms, edges: mstEdges, tiles: &tiles, story: 0, corridorWidth: corridorWidth)

        let topRight = topRightRoom(from: rooms)
        let spawn = spawnCell(for: topRight)
        ensureReachability(rooms: rooms, spawn: spawn, tiles: &tiles, story: 0, corridorWidth: corridorWidth)

        // Widen hallways before sealing so room rings stay closed afterward.
        enforceMinTraversableWidth(
            tiles: &tiles,
            story: 0,
            roomCells: rooms.reduce(into: Set()) { $0.formUnion($1.cells) }
        )
        sealAllRoomPerimeters(rooms: rooms, tiles: &tiles, story: 0)
        markDestructibleWalls(in: &tiles[0], chance: params.wallDestructibleChance, rng: &rng)

        // Pits only on floors that already touch a wall — never replace walls/doors.
        sprinklePits(into: &tiles[0], chance: params.pitChance, excluding: spawn, rng: &rng)
        clearPits(around: spawn, tiles: &tiles, story: 0)

        let letter = config.player.letter.first ?? "P"
        let player = GameEntity(letter: letter, position: spawn, isPlayer: true)
        var entities = [player]
        var occupied: Set<GridCoord> = [spawn]

        if let spawnConfig = config.enemies,
           let typeConfig = enemyConfig.type(named: spawnConfig.type) {
            let enemies = spawnEnemies(
                in: rooms,
                excludingRoomID: topRight.id,
                tiles: tiles,
                typeID: spawnConfig.type,
                typeConfig: typeConfig,
                chance: spawnConfig.spawnChancePerRoom,
                occupied: &occupied,
                rng: &rng
            )
            entities.append(contentsOf: enemies)
        }

        if let pickups = config.pickups {
            let spawned = spawnPickups(
                pickups,
                in: rooms,
                excludingRoomID: topRight.id,
                tiles: tiles,
                occupied: &occupied,
                rng: &rng
            )
            entities.append(contentsOf: spawned)
        }

        let world = GameWorld(
            width: width,
            height: height,
            storyCount: stories,
            tiles: tiles,
            entities: entities,
            spawn: spawn
        )

        return GenerationResult(
            world: world,
            rooms: rooms,
            topRightRoomID: topRight.id,
            joinPairs: mstEdges
        )
    }

    /// One roll per room (except the spawn room); place on a walkable non-pit floor cell.
    private func spawnEnemies(
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        typeID: String,
        typeConfig: EnemyTypeConfig,
        chance: Double,
        occupied: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> [GameEntity] {
        var enemies: [GameEntity] = []

        for room in rooms where room.id != excludingRoomID {
            guard rng.nextBool(probability: chance) else { continue }
            guard let position = pickSpawnCell(
                in: room,
                tiles: tiles,
                occupied: occupied,
                rng: &rng
            ) else { continue }

            occupied.insert(position)
            enemies.append(
                GameEntity(
                    letter: typeConfig.letterCharacter,
                    position: position,
                    isPlayer: false,
                    enemyTypeID: typeID
                )
            )
        }

        return enemies
    }

    /// One roll per room per kind (except the spawn room); place on a walkable non-pit floor cell.
    private func spawnPickups(
        _ config: WorldSeedConfig.PickupsSpawnConfig,
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> [GameEntity] {
        var pickups: [GameEntity] = []
        let kinds: [(PickupKind, Double?)] = [
            (.health, config.health?.spawnChancePerRoom),
            (.energy, config.energy?.spawnChancePerRoom),
            (.treasure, config.treasure?.spawnChancePerRoom),
        ]

        for (kind, chance) in kinds {
            guard let chance else { continue }
            for room in rooms where room.id != excludingRoomID {
                guard rng.nextBool(probability: chance) else { continue }
                guard let position = pickSpawnCell(
                    in: room,
                    tiles: tiles,
                    occupied: occupied,
                    rng: &rng
                ) else { continue }

                occupied.insert(position)
                pickups.append(
                    GameEntity(
                        letter: " ",
                        position: position,
                        isPlayer: false,
                        pickupKind: kind
                    )
                )
            }
        }

        return pickups
    }

    private func pickSpawnCell(
        in room: GeneratedRoom,
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GridCoord? {
        let candidates = room.cells
            .filter { cell in
                guard !occupied.contains(cell) else { return false }
                let tile = tiles[0][cell.y][cell.x]
                if case .floor(let isPit) = tile.kind {
                    return !isPit
                }
                return false
            }
            .sorted { lhs, rhs in
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.y < rhs.y
            }
        return rng.pick(candidates)
    }

    // MARK: - Room placement

    private func filledWalls(width: Int, height: Int, stories: Int) -> [[[Tile]]] {
        Array(
            repeating: Array(
                repeating: Array(
                    repeating: Tile(kind: .wall(destructible: false, hasDoor: false)),
                    count: width
                ),
                count: height
            ),
            count: stories
        )
    }

    /// Scatter organic rooms (rects + long L-shapes). Unused map tiles stay solid wall.
    private func placeOrganicRooms(
        count: Int,
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> [GeneratedRoom] {
        var rooms: [GeneratedRoom] = []
        var occupied = Set<GridCoord>()
        let maxAttempts = max(count * 120, 200)

        for _ in 0..<maxAttempts where rooms.count < count {
            let cells: Set<GridCoord>
            // Bias toward L-shapes for a more organic floorplan.
            if rng.nextBool(probability: 0.55) {
                cells = makeOrganicLRoom(
                    minSize: minSize,
                    maxSize: maxSize,
                    width: width,
                    height: height,
                    rng: &rng
                )
            } else {
                cells = makeOrganicRectRoom(
                    minSize: minSize,
                    maxSize: maxSize,
                    width: width,
                    height: height,
                    rng: &rng
                )
            }

            guard !cells.isEmpty else { continue }

            let buffered = buffer(cells: cells, width: width, height: height, padding: 1)
            if !buffered.isDisjoint(with: occupied) { continue }

            occupied.formUnion(buffered)
            let center = centroid(of: cells)
            rooms.append(
                GeneratedRoom(
                    id: rooms.count,
                    cells: cells,
                    center: center,
                    latticeX: 0,
                    latticeY: 0
                )
            )
        }

        return rooms
    }

    private func makeOrganicRectRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let w = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let h = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        // Occasional long corridor-like rooms.
        let stretch = rng.nextBool(probability: 0.25)
        let finalW = stretch && rng.nextBool(probability: 0.5) ? min(width - 2, w + maxSize) : w
        let finalH = stretch && finalW == w ? min(height - 2, h + maxSize) : h
        guard width > finalW + 2, height > finalH + 2 else { return [] }

        let x = rng.nextInt(upperBound: width - finalW - 1) + 1
        let y = rng.nextInt(upperBound: height - finalH - 1) + 1

        var cells = Set<GridCoord>()
        for row in y..<(y + finalH) {
            for col in x..<(x + finalW) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }
        return cells
    }

    /// L-shape from two overlapping rects; arms may be long (up to ~2× maxSize).
    private func makeOrganicLRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let longMax = maxSize * 2
        let armW = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let armH = rng.nextInt(upperBound: longMax - minSize + 1) + minSize
        let crossW = rng.nextInt(upperBound: longMax - minSize + 1) + minSize
        let crossH = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize

        guard width > max(armW, crossW) + 2, height > max(armH, crossH) + 2 else { return [] }

        let maxOriginX = width - max(armW, crossW) - 1
        let maxOriginY = height - max(armH, crossH) - 1
        guard maxOriginX >= 1, maxOriginY >= 1 else { return [] }

        let x = rng.nextInt(upperBound: maxOriginX) + 1
        let y = rng.nextInt(upperBound: maxOriginY) + 1

        var cells = Set<GridCoord>()
        for row in y..<min(height - 1, y + armH) {
            for col in x..<min(width - 1, x + armW) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }

        // Attach the cross-bar at one of the four corners of the primary arm.
        let corner = rng.nextInt(upperBound: 4)
        let crossX: Int
        let crossY: Int
        switch corner {
        case 0: // top-left of primary
            crossX = x
            crossY = y
        case 1: // top-right
            crossX = max(1, x + armW - crossW)
            crossY = y
        case 2: // bottom-left
            crossX = x
            crossY = max(1, y + armH - crossH)
        default: // bottom-right
            crossX = max(1, x + armW - crossW)
            crossY = max(1, y + armH - crossH)
        }

        for row in crossY..<min(height - 1, crossY + crossH) {
            for col in crossX..<min(width - 1, crossX + crossW) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
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

    /// Prim MST over room centers (Manhattan). Prefers nearby rooms for short joins.
    private func geometricMST(for rooms: [GeneratedRoom]) -> [(Int, Int)] {
        guard rooms.count > 1 else { return [] }

        var inTree = Set([0])
        var edges: [(Int, Int)] = []

        while inTree.count < rooms.count {
            var best: (Int, Int, Int)?
            for i in inTree {
                for j in 0..<rooms.count where !inTree.contains(j) {
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

    private func joinRooms(
        rooms: [GeneratedRoom],
        edges: [(Int, Int)],
        tiles: inout [[[Tile]]],
        story: Int,
        corridorWidth: Int
    ) {
        for (aIndex, bIndex) in edges {
            joinRoomsWithDoorOrTunnel(
                rooms[aIndex],
                rooms[bIndex],
                tiles: &tiles,
                story: story,
                corridorWidth: corridorWidth
            )
        }
    }

    /// Door through a shared wall when rooms touch; otherwise a wide L-tunnel with doors.
    private func joinRoomsWithDoorOrTunnel(
        _ roomA: GeneratedRoom,
        _ roomB: GeneratedRoom,
        tiles: inout [[[Tile]]],
        story: Int,
        corridorWidth: Int
    ) {
        let width = max(2, corridorWidth)

        if let opening = sharedWallOpening(roomA, roomB) {
            placeDoorStrip(
                at: opening.wall,
                alongDX: opening.alongDX,
                alongDY: opening.alongDY,
                width: width,
                tiles: &tiles,
                story: story,
                requiresSharedWallBetween: (roomA, roomB)
            )
            return
        }

        let (start, end) = closestPair(roomA, roomB)
        if manhattan(start, end) == 2 {
            let mid = GridCoord(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2, story: story)
            let stepX = (end.x - start.x).signum()
            let stepY = (end.y - start.y).signum()
            // Perpendicular to the one-cell gap.
            placeDoorStrip(
                at: mid,
                alongDX: -stepY,
                alongDY: stepX,
                width: width,
                tiles: &tiles,
                story: story,
                requiresSharedWallBetween: nil
            )
            return
        }

        let path = lPath(from: start, to: end)
        carveThickCorridor(
            along: path,
            width: width,
            excluding: roomA.cells.union(roomB.cells),
            tiles: &tiles,
            story: story
        )

        sealRoomExitsWithDoors(room: roomA, tiles: &tiles, story: story)
        sealRoomExitsWithDoors(room: roomB, tiles: &tiles, story: story)
    }

    /// Carves a corridor of `width` tiles along an L-path using a square brush so bends stay wide.
    private func carveThickCorridor(
        along path: [GridCoord],
        width: Int,
        excluding: Set<GridCoord>,
        tiles: inout [[[Tile]]],
        story: Int
    ) {
        guard !path.isEmpty else { return }
        let offsets = thicknessOffsets(width: width)

        for coord in path {
            for ox in offsets {
                for oy in offsets {
                    let carved = GridCoord(x: coord.x + ox, y: coord.y + oy, story: story)
                    guard !excluding.contains(carved) else { continue }
                    guard carved.y >= 0, carved.y < tiles[story].count else { continue }
                    guard carved.x >= 0, carved.x < tiles[story][carved.y].count else { continue }
                    if case .wall = tiles[story][carved.y][carved.x].kind {
                        tiles[story][carved.y][carved.x] = Tile(kind: .floor(isPit: false))
                    }
                }
            }
        }
    }

    private func thicknessOffsets(width: Int) -> [Int] {
        let start = -((width - 1) / 2)
        return Array(start..<(start + width))
    }

    private func placeDoorStrip(
        at origin: GridCoord,
        alongDX: Int,
        alongDY: Int,
        width: Int,
        tiles: inout [[[Tile]]],
        story: Int,
        requiresSharedWallBetween rooms: (GeneratedRoom, GeneratedRoom)?
    ) {
        let dx = alongDX == 0 && alongDY == 0 ? 1 : alongDX
        let dy = alongDX == 0 && alongDY == 0 ? 0 : alongDY
        for i in 0..<width {
            let coord = GridCoord(x: origin.x + dx * i, y: origin.y + dy * i, story: story)
            // Prefer true shared-wall cells, but still open the full strip so doorways stay wide.
            if let (roomA, roomB) = rooms, !isSharedWall(coord, between: roomA, and: roomB) {
                guard coord.y >= 0, coord.y < tiles[story].count else { continue }
                guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { continue }
                if case .wall = tiles[story][coord.y][coord.x].kind {
                    setDoor(at: coord, tiles: &tiles, story: story)
                }
                continue
            }
            setDoor(at: coord, tiles: &tiles, story: story)
        }
    }

    /// Re-seal every room so corridors/widening never leave an open floor gap in a room ring.
    private func sealAllRoomPerimeters(
        rooms: [GeneratedRoom],
        tiles: inout [[[Tile]]],
        story: Int
    ) {
        let ordered = rooms.sorted { $0.id < $1.id }
        for room in ordered {
            sealRoomExitsWithDoors(room: room, tiles: &tiles, story: story)
        }
    }

    /// Any open floor orthogonally adjacent to a room becomes a door so rooms stay gated.
    private func sealRoomExitsWithDoors(
        room: GeneratedRoom,
        tiles: inout [[[Tile]]],
        story: Int
    ) {
        let cells = room.cells.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        for cell in cells {
            for (dx, dy) in GridCoord.cardinals {
                let neighbor = cell.neighbor(dx: dx, dy: dy)
                guard !room.cells.contains(neighbor) else { continue }
                guard neighbor.y >= 0, neighbor.y < tiles[story].count else { continue }
                guard neighbor.x >= 0, neighbor.x < tiles[story][neighbor.y].count else { continue }
                if isFloor(tiles[story][neighbor.y][neighbor.x]) {
                    setDoor(at: neighbor, tiles: &tiles, story: story)
                }
            }
        }
    }

    private func isDoor(_ tile: Tile) -> Bool {
        if case .wall(_, true) = tile.kind { return true }
        return false
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

    /// Shared wall cell plus the direction along the wall (perpendicular to the room-to-room step).
    private func sharedWallOpening(
        _ roomA: GeneratedRoom,
        _ roomB: GeneratedRoom
    ) -> (wall: GridCoord, alongDX: Int, alongDY: Int)? {
        let cellsA = roomA.cells.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        for cell in cellsA {
            for (dx, dy) in GridCoord.cardinals {
                let wall = cell.neighbor(dx: dx, dy: dy)
                let beyond = wall.neighbor(dx: dx, dy: dy)
                if roomB.cells.contains(beyond) {
                    return (wall, -dy, dx)
                }
            }
        }
        return nil
    }

    private func isSharedWall(
        _ wall: GridCoord,
        between roomA: GeneratedRoom,
        and roomB: GeneratedRoom
    ) -> Bool {
        for (dx, dy) in GridCoord.cardinals {
            let a = wall.neighbor(dx: dx, dy: dy)
            let b = wall.neighbor(dx: -dx, dy: -dy)
            if roomA.cells.contains(a), roomB.cells.contains(b) { return true }
            if roomB.cells.contains(a), roomA.cells.contains(b) { return true }
        }
        return false
    }

    private func setDoor(at coord: GridCoord, tiles: inout [[[Tile]]], story: Int) {
        guard coord.y >= 0, coord.y < tiles[story].count else { return }
        guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { return }

        switch tiles[story][coord.y][coord.x].kind {
        case .wall(let destructible, _):
            tiles[story][coord.y][coord.x] = Tile(kind: .wall(destructible: destructible, hasDoor: true))
        case .floor:
            tiles[story][coord.y][coord.x] = Tile(kind: .wall(destructible: false, hasDoor: true))
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

    private func topRightRoom(from rooms: [GeneratedRoom]) -> GeneratedRoom {
        rooms.max { lhs, rhs in
            let lhsScore = (lhs.center.x - lhs.center.y, -(lhs.center.x + lhs.center.y))
            let rhsScore = (rhs.center.x - rhs.center.y, -(rhs.center.x + rhs.center.y))
            return lhsScore < rhsScore
        } ?? rooms[0]
    }

    // MARK: - Passage width

    /// Widens any remaining 1-tile-wide hallway/door runs by opening a parallel passage.
    private func enforceMinTraversableWidth(
        tiles: inout [[[Tile]]],
        story: Int,
        roomCells: Set<GridCoord>
    ) {
        var changed = true
        var guardCounter = 0
        while changed, guardCounter < 64 {
            changed = false
            guardCounter += 1
            for y in 0..<tiles[story].count {
                for x in 0..<tiles[story][y].count {
                    let coord = GridCoord(x: x, y: y, story: story)
                    guard !roomCells.contains(coord) else { continue }
                    guard isEnterable(tiles[story][y][x]) else { continue }
                    guard isSingleFilePassage(coord, tiles: tiles, story: story) else { continue }

                    let sideOffsets: [(Int, Int)]
                    let alongOffsets: [(Int, Int)]
                    if isNorthSouthFile(coord, tiles: tiles, story: story) {
                        sideOffsets = [(1, 0), (-1, 0)]
                        alongOffsets = [(0, -1), (0, 1)]
                    } else {
                        sideOffsets = [(0, 1), (0, -1)]
                        alongOffsets = [(-1, 0), (1, 0)]
                    }

                    for (sx, sy) in sideOffsets {
                        let side = coord.neighbor(dx: sx, dy: sy)
                        guard carveFloorIfSolidWall(side, tiles: &tiles, story: story) else { continue }
                        // Mirror open connections along the passage so we don't leave a 1-tile spur.
                        for (ax, ay) in alongOffsets {
                            if isEnterableNeighbor(coord, dx: ax, dy: ay, tiles: tiles, story: story) {
                                _ = carveFloorIfSolidWall(
                                    side.neighbor(dx: ax, dy: ay),
                                    tiles: &tiles,
                                    story: story
                                )
                            }
                        }
                        changed = true
                        break
                    }
                }
            }
        }
    }

    @discardableResult
    private func carveFloorIfSolidWall(
        _ coord: GridCoord,
        tiles: inout [[[Tile]]],
        story: Int
    ) -> Bool {
        guard coord.y >= 0, coord.y < tiles[story].count else { return false }
        guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { return false }
        if case .wall(_, let hasDoor) = tiles[story][coord.y][coord.x].kind, !hasDoor {
            tiles[story][coord.y][coord.x] = Tile(kind: .floor(isPit: false))
            return true
        }
        return false
    }

    private func isSingleFilePassage(_ coord: GridCoord, tiles: [[[Tile]]], story: Int) -> Bool {
        isNorthSouthFile(coord, tiles: tiles, story: story) || isEastWestFile(coord, tiles: tiles, story: story)
    }

    private func isNorthSouthFile(_ coord: GridCoord, tiles: [[[Tile]]], story: Int) -> Bool {
        let n = isEnterableNeighbor(coord, dx: 0, dy: -1, tiles: tiles, story: story)
        let s = isEnterableNeighbor(coord, dx: 0, dy: 1, tiles: tiles, story: story)
        let e = isEnterableNeighbor(coord, dx: 1, dy: 0, tiles: tiles, story: story)
        let w = isEnterableNeighbor(coord, dx: -1, dy: 0, tiles: tiles, story: story)
        return (n || s) && !e && !w
    }

    private func isEastWestFile(_ coord: GridCoord, tiles: [[[Tile]]], story: Int) -> Bool {
        let n = isEnterableNeighbor(coord, dx: 0, dy: -1, tiles: tiles, story: story)
        let s = isEnterableNeighbor(coord, dx: 0, dy: 1, tiles: tiles, story: story)
        let e = isEnterableNeighbor(coord, dx: 1, dy: 0, tiles: tiles, story: story)
        let w = isEnterableNeighbor(coord, dx: -1, dy: 0, tiles: tiles, story: story)
        return (e || w) && !n && !s
    }

    private func isEnterableNeighbor(
        _ coord: GridCoord,
        dx: Int,
        dy: Int,
        tiles: [[[Tile]]],
        story: Int
    ) -> Bool {
        let next = coord.neighbor(dx: dx, dy: dy)
        guard next.y >= 0, next.y < tiles[story].count else { return false }
        guard next.x >= 0, next.x < tiles[story][next.y].count else { return false }
        return isEnterable(tiles[story][next.y][next.x])
    }

    // MARK: - Reachability repair

    private func ensureReachability(
        rooms: [GeneratedRoom],
        spawn: GridCoord,
        tiles: inout [[[Tile]]],
        story: Int,
        corridorWidth: Int
    ) {
        let ordered = rooms.sorted(by: { $0.id < $1.id })
        for room in ordered {
            guard !roomReachable(room, from: spawn, tiles: tiles, story: story) else { continue }
            if let other = ordered.first(where: { roomReachable($0, from: spawn, tiles: tiles, story: story) }) {
                joinRoomsWithDoorOrTunnel(
                    other,
                    room,
                    tiles: &tiles,
                    story: story,
                    corridorWidth: corridorWidth
                )
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
                // Only convert existing floors; walls/doors are never replaced by pits.
                guard case .floor = story[y][x].kind else { continue }
                guard hasWallNeighbor(x: x, y: y, in: story) else { continue }
                if rng.nextBool(probability: chance) {
                    story[y][x] = Tile(kind: .floor(isPit: true))
                }
            }
        }
    }

    /// Pits must sit against a wall (or door) tile so they never float in open floor.
    private func hasWallNeighbor(x: Int, y: Int, in story: [[Tile]]) -> Bool {
        for (dx, dy) in GridCoord.cardinals {
            let nx = x + dx
            let ny = y + dy
            guard ny >= 0, ny < story.count else { continue }
            guard nx >= 0, nx < story[ny].count else { continue }
            if case .wall = story[ny][nx].kind { return true }
        }
        return false
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
                if case .wall(false, false) = story[y][x].kind,
                   rng.nextBool(probability: chance) {
                    story[y][x] = Tile(kind: .wall(destructible: true, hasDoor: false))
                }
            }
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

    private func isEnterable(_ tile: Tile) -> Bool {
        switch tile.kind {
        case .floor:
            return true
        case .wall(_, let hasDoor):
            return hasDoor
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
