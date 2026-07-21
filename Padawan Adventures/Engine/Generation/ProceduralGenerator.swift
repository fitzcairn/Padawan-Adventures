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
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback
    ) throws -> GameWorld {
        try generateDetailed(from: config, playerConfig: playerConfig, enemyConfig: enemyConfig).world
    }

    func generateDetailed(
        from config: WorldSeedConfig,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback
    ) throws -> GenerationResult {
        try config.validate()
        try playerConfig.validate()

        var rng = SeededGenerator(seed: config.resolvedSeed())
        let width = config.world.width
        let height = config.world.height
        let stories = config.world.stories
        let params = config.generation

        var tiles = filledWalls(width: width, height: height, stories: stories)

        let rooms = placeOrganicRooms(
            count: params.roomCount,
            minSize: params.room.minRoomSize,
            maxSize: params.room.maxRoomSize,
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
        let roomCells = rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }

        // Widen hallways, then place soft blockers, then validate reachability through them.
        enforceMinTraversableWidth(tiles: &tiles, story: 0, roomCells: roomCells)
        markDestructibleWalls(
            rooms: rooms,
            in: &tiles[0],
            chance: params.room.wallDestructibleChance,
            rng: &rng
        )
        placeGates(
            rooms: rooms,
            tiles: &tiles,
            story: 0,
            spawn: spawn,
            corridorWidth: corridorWidth,
            rng: &rng
        )
        ensureReachability(rooms: rooms, spawn: spawn, tiles: &tiles, story: 0, corridorWidth: corridorWidth)

        // At most one pit per room, rolled with room.pit_chance.
        sprinklePits(
            rooms: rooms,
            into: &tiles[0],
            chance: params.room.pitChance,
            excludingRoomID: topRight.id,
            excluding: spawn,
            rng: &rng
        )
        clearPits(around: spawn, tiles: &tiles, story: 0)

        let letter = playerConfig.letter.first ?? "P"
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
            spawn: spawn,
            healthCount: playerConfig.startingHealth,
            energyCount: playerConfig.startingEnergy
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
                    repeating: Tile(kind: .wall(destructible: false)),
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

            // Allow a single shared wall between rooms (for destructible partitions), but never
            // floor-to-floor contact.
            guard cells.isDisjoint(with: occupied) else { continue }
            let touchesExistingFloor = cells.contains { cell in
                GridCoord.cardinals.contains { dx, dy in
                    occupied.contains(cell.neighbor(dx: dx, dy: dy))
                }
            }
            guard !touchesExistingFloor else { continue }

            occupied.formUnion(cells)
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

    /// Floor opening through a shared wall when rooms touch; otherwise a wide L-tunnel.
    private func joinRoomsWithDoorOrTunnel(
        _ roomA: GeneratedRoom,
        _ roomB: GeneratedRoom,
        tiles: inout [[[Tile]]],
        story: Int,
        corridorWidth: Int
    ) {
        let width = max(2, corridorWidth)

        if let opening = sharedWallOpening(roomA, roomB) {
            placeFloorOpeningStrip(
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
            placeFloorOpeningStrip(
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

    private func placeFloorOpeningStrip(
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
            // Prefer true shared-wall cells, but still open the full strip so passages stay wide.
            if let (roomA, roomB) = rooms, !isSharedWall(coord, between: roomA, and: roomB) {
                guard coord.y >= 0, coord.y < tiles[story].count else { continue }
                guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { continue }
                if case .wall = tiles[story][coord.y][coord.x].kind {
                    setFloorOpening(at: coord, tiles: &tiles, story: story)
                }
                continue
            }
            setFloorOpening(at: coord, tiles: &tiles, story: story)
        }
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

    private func setFloorOpening(at coord: GridCoord, tiles: inout [[[Tile]]], story: Int) {
        guard coord.y >= 0, coord.y < tiles[story].count else { return }
        guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { return }
        tiles[story][coord.y][coord.x] = Tile(kind: .floor(isPit: false))
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
        if case .wall(false) = tiles[story][coord.y][coord.x].kind {
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
                guard isGenerationPassable(tiles[story][next.y][next.x]) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return visited
    }

    // MARK: - Pits / walls / gates

    /// Rolls `chance` once per room; on success places a single pit floor in that room.
    private func sprinklePits(
        rooms: [GeneratedRoom],
        into story: inout [[Tile]],
        chance: Double,
        excludingRoomID: Int,
        excluding spawn: GridCoord,
        rng: inout SeededGenerator
    ) {
        let ordered = rooms.sorted { $0.id < $1.id }
        for room in ordered {
            guard room.id != excludingRoomID else { continue }
            guard rng.nextBool(probability: chance) else { continue }

            let candidates = room.cells
                .filter { cell in
                    guard cell != spawn else { return false }
                    guard case .floor(let isPit) = story[cell.y][cell.x].kind else { return false }
                    return !isPit
                }
                .sorted { lhs, rhs in
                    if lhs.x != rhs.x { return lhs.x < rhs.x }
                    return lhs.y < rhs.y
                }
            guard let pick = rng.pick(candidates) else { continue }
            story[pick.y][pick.x] = Tile(kind: .floor(isPit: true))
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

    /// One-tile soft walls only where a solid wall sits between two different rooms.
    private func markDestructibleWalls(
        rooms: [GeneratedRoom],
        in story: inout [[Tile]],
        chance: Double,
        rng: inout SeededGenerator
    ) {
        let roomByCell: [GridCoord: Int] = rooms.reduce(into: [:]) { map, room in
            for cell in room.cells {
                map[cell] = room.id
            }
        }

        for y in 0..<story.count {
            for x in 0..<story[y].count {
                guard case .wall(false) = story[y][x].kind else { continue }
                let coord = GridCoord(x: x, y: y, story: 0)
                guard isSingleTileRoomPartition(coord, roomByCell: roomByCell) else { continue }
                if rng.nextBool(probability: chance) {
                    story[y][x] = Tile(kind: .wall(destructible: true))
                }
            }
        }
    }

    private func isSingleTileRoomPartition(
        _ coord: GridCoord,
        roomByCell: [GridCoord: Int]
    ) -> Bool {
        for (dx, dy) in GridCoord.cardinals {
            let a = coord.neighbor(dx: dx, dy: dy)
            let b = coord.neighbor(dx: -dx, dy: -dy)
            guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
            return true
        }
        return false
    }

    /// Multi-tile gate strips that span a hallway cross-section.
    private func placeGates(
        rooms: [GeneratedRoom],
        tiles: inout [[[Tile]]],
        story: Int,
        spawn: GridCoord,
        corridorWidth: Int,
        rng: inout SeededGenerator
    ) {
        let roomCells = rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }
        let minWidth = max(2, corridorWidth)
        var candidates: [[GridCoord]] = []

        for y in 1..<(tiles[story].count - 1) {
            for x in 1..<(tiles[story][y].count - 1) {
                let coord = GridCoord(x: x, y: y, story: story)
                guard !roomCells.contains(coord), coord != spawn else { continue }
                guard case .floor = tiles[story][y][x].kind else { continue }

                // East-west travel: walls north & south of the band; strip runs along Y.
                if let strip = hallwayGateStrip(
                    seed: coord,
                    crossDX: 0,
                    crossDY: 1,
                    minWidth: minWidth,
                    tiles: tiles,
                    story: story,
                    roomCells: roomCells,
                    spawn: spawn
                ) {
                    candidates.append(strip)
                }
                // North-south travel: walls west & east of the band; strip runs along X.
                if let strip = hallwayGateStrip(
                    seed: coord,
                    crossDX: 1,
                    crossDY: 0,
                    minWidth: minWidth,
                    tiles: tiles,
                    story: story,
                    roomCells: roomCells,
                    spawn: spawn
                ) {
                    candidates.append(strip)
                }
            }
        }

        // Deduplicate identical strips.
        var unique: [[GridCoord]] = []
        var seen = Set<Set<GridCoord>>()
        for strip in candidates {
            let key = Set(strip)
            guard seen.insert(key).inserted else { continue }
            unique.append(strip.sorted { ($0.x, $0.y) < ($1.x, $1.y) })
        }
        unique.sort { lhs, rhs in
            let a = lhs[0]
            let b = rhs[0]
            if a.x != b.x { return a.x < b.x }
            return a.y < b.y
        }

        let target = max(2, rooms.count / 4)
        var placed = 0
        var blocked = Set<GridCoord>()

        for strip in unique {
            guard placed < target else { break }
            guard strip.allSatisfy({ !blocked.contains($0) }) else { continue }
            // Prefer placing most candidates so gates reliably appear.
            guard placed < 2 || rng.nextBool(probability: 0.7) else { continue }

            for cell in strip {
                tiles[story][cell.y][cell.x] = Tile(kind: .gate)
                blocked.insert(cell)
            }
            // Keep gates from clustering too tightly along a corridor.
            if let first = strip.first, let last = strip.last {
                for cell in [first, last] {
                    for (dx, dy) in GridCoord.cardinals {
                        blocked.insert(cell.neighbor(dx: dx * 2, dy: dy * 2))
                    }
                }
            }
            placed += 1
        }
    }

    /// Builds a gate strip across a hallway: expand from `seed` along the cross-axis until walls.
    private func hallwayGateStrip(
        seed: GridCoord,
        crossDX: Int,
        crossDY: Int,
        minWidth: Int,
        tiles: [[[Tile]]],
        story: Int,
        roomCells: Set<GridCoord>,
        spawn: GridCoord
    ) -> [GridCoord]? {
        // Travel axis is perpendicular to the cross-axis; both travel neighbors should be open-ish.
        let travelDX = crossDY
        let travelDY = -crossDX

        func inBounds(_ c: GridCoord) -> Bool {
            c.y >= 0 && c.y < tiles[story].count && c.x >= 0 && c.x < tiles[story][c.y].count
        }
        func isHallFloor(_ c: GridCoord) -> Bool {
            guard inBounds(c), !roomCells.contains(c), c != spawn else { return false }
            return isFloor(tiles[story][c.y][c.x])
        }
        func isBlockingWall(_ c: GridCoord) -> Bool {
            guard inBounds(c) else { return true }
            return isSolidWall(tiles[story][c.y][c.x])
        }

        // Must be able to travel along the corridor on at least one side.
        let ahead = seed.neighbor(dx: travelDX, dy: travelDY)
        let behind = seed.neighbor(dx: -travelDX, dy: -travelDY)
        guard isHallFloor(ahead) || isHallFloor(behind) else { return nil }

        // Expand along cross-axis to the hallway walls.
        var strip = [seed]
        var cursor = seed.neighbor(dx: crossDX, dy: crossDY)
        while isHallFloor(cursor) {
            strip.append(cursor)
            cursor = cursor.neighbor(dx: crossDX, dy: crossDY)
        }
        guard isBlockingWall(cursor) else { return nil }

        cursor = seed.neighbor(dx: -crossDX, dy: -crossDY)
        while isHallFloor(cursor) {
            strip.insert(cursor, at: 0)
            cursor = cursor.neighbor(dx: -crossDX, dy: -crossDY)
        }
        guard isBlockingWall(cursor) else { return nil }

        guard strip.count >= minWidth else { return nil }
        // Keep strips modest so we don't gate entire rooms-worth of hallway.
        guard strip.count <= minWidth + 2 else { return nil }
        return strip
    }

    private func isSolidWall(_ tile: Tile) -> Bool {
        if case .wall = tile.kind { return true }
        return false
    }

    // MARK: - Helpers

    private func manhattan(_ a: GridCoord, _ b: GridCoord) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func isFloor(_ tile: Tile) -> Bool {
        if case .floor = tile.kind { return true }
        return false
    }

    /// Gameplay enterability for hallway widening (floors only — soft blockers placed later).
    private func isEnterable(_ tile: Tile) -> Bool {
        if case .floor = tile.kind { return true }
        return false
    }

    /// Generation reachability treats destructible walls and gates as already passable.
    private func isGenerationPassable(_ tile: Tile) -> Bool {
        switch tile.kind {
        case .floor, .gate:
            return true
        case .wall(let destructible):
            return destructible
        }
    }
}
