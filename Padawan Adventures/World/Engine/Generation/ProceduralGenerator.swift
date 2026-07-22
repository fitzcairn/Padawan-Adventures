import Foundation

nonisolated struct GeneratedRoom: Equatable, Sendable {
    let id: Int
    let cells: Set<GridCoord>
    let center: GridCoord
    /// Lattice coordinates used for packed-room adjacency.
    let latticeX: Int
    let latticeY: Int
}

nonisolated struct GenerationResult: Sendable {
    let world: GameWorld
    let rooms: [GeneratedRoom]
    let topRightRoomID: Int
    let joinPairs: [(Int, Int)]
}

nonisolated struct ProceduralGenerator: Sendable {
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
        var doorOpenings = joinRooms(
            rooms: rooms,
            edges: mstEdges,
            tiles: &tiles,
            story: 0,
            corridorWidth: corridorWidth
        )

        let topRight = topRightRoom(from: rooms)
        let spawn = spawnCell(for: topRight)
        let roomCells = rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }

        // Widen hallways, repair reachability, then place door gates and soft walls.
        enforceMinTraversableWidth(tiles: &tiles, story: 0, roomCells: roomCells)
        doorOpenings += ensureReachability(
            rooms: rooms,
            spawn: spawn,
            tiles: &tiles,
            story: 0,
            corridorWidth: corridorWidth
        )
        placeGatesOnDoorOpenings(
            doorOpenings,
            rooms: rooms,
            tiles: &tiles,
            story: 0,
            chance: params.room.gateChance,
            rng: &rng
        )
        markDestructibleWalls(
            rooms: rooms,
            in: &tiles[0],
            chance: params.room.wallDestructibleChance,
            rng: &rng
        )

        // At most one pit area per room, rolled with room.pit_chance.
        sprinklePits(
            rooms: rooms,
            into: &tiles[0],
            chance: params.room.pitChance,
            meanSize: params.room.pitMeanSize,
            maxSize: params.room.pitMaxSize,
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

        if let treasure = spawnTreasure(
            in: rooms,
            spawn: spawn,
            tiles: tiles,
            occupied: &occupied,
            rng: &rng
        ) {
            entities.append(treasure)
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

    /// One roll per room (except the spawn room); place on a room floor cell only.
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
            guard let position = pickRoomFloorCell(
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

    /// One roll per room per kind (except the spawn room); place on a room floor cell only.
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
        ]

        for (kind, chance) in kinds {
            guard let chance else { continue }
            for room in rooms where room.id != excludingRoomID {
                guard rng.nextBool(probability: chance) else { continue }
                guard let position = pickRoomFloorCell(
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

    /// Places exactly one treasure in the room farthest from spawn (tile Manhattan distance).
    private func spawnTreasure(
        in rooms: [GeneratedRoom],
        spawn: GridCoord,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GameEntity? {
        guard let room = farthestRoom(from: spawn, in: rooms) else { return nil }
        guard let position = pickRoomFloorCell(
            in: room,
            tiles: tiles,
            occupied: occupied,
            rng: &rng
        ) else { return nil }

        occupied.insert(position)
        return GameEntity(
            letter: " ",
            position: position,
            isPlayer: false,
            pickupKind: .treasure
        )
    }

    /// Room whose center is farthest from `spawn` by Manhattan distance (ties → higher room id).
    private func farthestRoom(from spawn: GridCoord, in rooms: [GeneratedRoom]) -> GeneratedRoom? {
        rooms.max { lhs, rhs in
            let lhsDist = manhattan(spawn, lhs.center)
            let rhsDist = manhattan(spawn, rhs.center)
            if lhsDist != rhsDist { return lhsDist < rhsDist }
            return lhs.id < rhs.id
        }
    }

    /// Picks a cell for pickups or enemies: room floor only (never pit, gate, wall, or hallway).
    private func pickRoomFloorCell(
        in room: GeneratedRoom,
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GridCoord? {
        let candidates = room.cells
            .filter { cell in
                guard !occupied.contains(cell) else { return false }
                return isEntityPlaceableRoomFloor(cell, in: room, tiles: tiles)
            }
            .sorted { lhs, rhs in
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.y < rhs.y
            }
        return rng.pick(candidates)
    }

    /// True only for non-pit floor tiles inside the given room (pickups and enemy sprites).
    private func isEntityPlaceableRoomFloor(
        _ cell: GridCoord,
        in room: GeneratedRoom,
        tiles: [[[Tile]]]
    ) -> Bool {
        guard room.cells.contains(cell) else { return false }
        guard cell.y >= 0, cell.y < tiles[0].count else { return false }
        guard cell.x >= 0, cell.x < tiles[0][cell.y].count else { return false }
        switch tiles[0][cell.y][cell.x].kind {
        case .floor(let isPit):
            return !isPit
        case .gate, .wall:
            return false
        }
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

    /// Cells carved as a door-style floor opening (eligible for gates).
    private struct DoorOpening: Equatable {
        var cells: [GridCoord]
    }

    @discardableResult
    private func joinRooms(
        rooms: [GeneratedRoom],
        edges: [(Int, Int)],
        tiles: inout [[[Tile]]],
        story: Int,
        corridorWidth: Int
    ) -> [DoorOpening] {
        var openings: [DoorOpening] = []
        for (aIndex, bIndex) in edges {
            if let opening = joinRoomsWithDoorOrTunnel(
                rooms[aIndex],
                rooms[bIndex],
                tiles: &tiles,
                story: story,
                corridorWidth: corridorWidth
            ) {
                openings.append(opening)
            }
        }
        return openings
    }

    /// Floor opening through a shared wall when rooms touch; otherwise a wide L-tunnel.
    /// Returns a door opening when a strip door was carved (not long corridors).
    @discardableResult
    private func joinRoomsWithDoorOrTunnel(
        _ roomA: GeneratedRoom,
        _ roomB: GeneratedRoom,
        tiles: inout [[[Tile]]],
        story: Int,
        corridorWidth: Int
    ) -> DoorOpening? {
        let width = max(2, corridorWidth)

        if let opening = sharedWallOpening(roomA, roomB) {
            let cells = placeFloorOpeningStrip(
                at: opening.wall,
                alongDX: opening.alongDX,
                alongDY: opening.alongDY,
                width: width,
                tiles: &tiles,
                story: story,
                requiresSharedWallBetween: (roomA, roomB)
            )
            return cells.isEmpty ? nil : DoorOpening(cells: cells)
        }

        let (start, end) = closestPair(roomA, roomB)
        if manhattan(start, end) == 2 {
            let mid = GridCoord(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2, story: story)
            let stepX = (end.x - start.x).signum()
            let stepY = (end.y - start.y).signum()
            // Perpendicular to the one-cell gap.
            let cells = placeFloorOpeningStrip(
                at: mid,
                alongDX: -stepY,
                alongDY: stepX,
                width: width,
                tiles: &tiles,
                story: story,
                requiresSharedWallBetween: nil
            )
            return cells.isEmpty ? nil : DoorOpening(cells: cells)
        }

        let path = lPath(from: start, to: end)
        carveThickCorridor(
            along: path,
            width: width,
            excluding: roomA.cells.union(roomB.cells),
            tiles: &tiles,
            story: story
        )
        return nil
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

    @discardableResult
    private func placeFloorOpeningStrip(
        at origin: GridCoord,
        alongDX: Int,
        alongDY: Int,
        width: Int,
        tiles: inout [[[Tile]]],
        story: Int,
        requiresSharedWallBetween rooms: (GeneratedRoom, GeneratedRoom)?
    ) -> [GridCoord] {
        let dx = alongDX == 0 && alongDY == 0 ? 1 : alongDX
        let dy = alongDX == 0 && alongDY == 0 ? 0 : alongDY
        var opened: [GridCoord] = []
        for i in 0..<width {
            let coord = GridCoord(x: origin.x + dx * i, y: origin.y + dy * i, story: story)
            // Prefer true shared-wall cells, but still open the full strip so passages stay wide.
            if let (roomA, roomB) = rooms, !isSharedWall(coord, between: roomA, and: roomB) {
                guard coord.y >= 0, coord.y < tiles[story].count else { continue }
                guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { continue }
                if case .wall = tiles[story][coord.y][coord.x].kind {
                    setFloorOpening(at: coord, tiles: &tiles, story: story)
                    opened.append(coord)
                }
                continue
            }
            if setFloorOpening(at: coord, tiles: &tiles, story: story) {
                opened.append(coord)
            }
        }
        return opened
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

    @discardableResult
    private func setFloorOpening(at coord: GridCoord, tiles: inout [[[Tile]]], story: Int) -> Bool {
        guard coord.y >= 0, coord.y < tiles[story].count else { return false }
        guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { return false }
        tiles[story][coord.y][coord.x] = Tile(kind: .floor(isPit: false))
        return true
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

    @discardableResult
    private func ensureReachability(
        rooms: [GeneratedRoom],
        spawn: GridCoord,
        tiles: inout [[[Tile]]],
        story: Int,
        corridorWidth: Int
    ) -> [DoorOpening] {
        var openings: [DoorOpening] = []
        let ordered = rooms.sorted(by: { $0.id < $1.id })
        for room in ordered {
            guard !roomReachable(room, from: spawn, tiles: tiles, story: story) else { continue }
            if let other = ordered.first(where: { roomReachable($0, from: spawn, tiles: tiles, story: story) }) {
                if let opening = joinRoomsWithDoorOrTunnel(
                    other,
                    room,
                    tiles: &tiles,
                    story: story,
                    corridorWidth: corridorWidth
                ) {
                    openings.append(opening)
                }
            }
        }
        return openings
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

    /// Rolls `chance` once per room; on success places a contiguous pit area in that room.
    private func sprinklePits(
        rooms: [GeneratedRoom],
        into story: inout [[Tile]],
        chance: Double,
        meanSize: Double,
        maxSize: Int,
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
            guard let seed = rng.pick(candidates) else { continue }

            let target = samplePitTileCount(mean: meanSize, maxSize: maxSize, rng: &rng)
            let area = growContiguousPit(
                from: seed,
                targetCount: target,
                roomCells: room.cells,
                excluding: spawn,
                in: story,
                rng: &rng
            )
            for cell in area {
                story[cell.y][cell.x] = Tile(kind: .floor(isPit: true))
            }
        }
    }

    /// Samples a pit size in `1...maxSize` with expected value ≈ `mean` via successive growth.
    private func samplePitTileCount(
        mean: Double,
        maxSize: Int,
        rng: inout SeededGenerator
    ) -> Int {
        let maxS = max(1, maxSize)
        let mu = min(Double(maxS), max(1.0, mean))
        if mu >= Double(maxS) - 1e-9 { return maxS }
        if mu <= 1.0 + 1e-9 { return 1 }

        let growthP = pitGrowthProbability(forMean: mu, maxSize: maxS)
        var count = 1
        while count < maxS && rng.nextBool(probability: growthP) {
            count += 1
        }
        return count
    }

    /// Growth probability `p` such that `E[1 + sum I_k] ≈ mean` for max `maxSize` steps.
    private func pitGrowthProbability(forMean mean: Double, maxSize: Int) -> Double {
        // E = (1 - p^n) / (1 - p) for p ∈ [0, 1), n = maxSize.
        var lo = 0.0
        var hi = 0.999_999
        for _ in 0..<48 {
            let mid = (lo + hi) * 0.5
            let expected = (1 - pow(mid, Double(maxSize))) / (1 - mid)
            if expected < mean {
                lo = mid
            } else {
                hi = mid
            }
        }
        return (lo + hi) * 0.5
    }

    /// Grows a contiguous pit blob inside a room via random frontier expansion.
    private func growContiguousPit(
        from seed: GridCoord,
        targetCount: Int,
        roomCells: Set<GridCoord>,
        excluding spawn: GridCoord,
        in story: [[Tile]],
        rng: inout SeededGenerator
    ) -> [GridCoord] {
        var area = [seed]
        var inArea: Set<GridCoord> = [seed]
        var frontier: [GridCoord] = []

        func consider(_ cell: GridCoord) {
            guard roomCells.contains(cell), cell != spawn, !inArea.contains(cell) else { return }
            guard case .floor(let isPit) = story[cell.y][cell.x].kind, !isPit else { return }
            if !frontier.contains(where: { $0 == cell }) {
                frontier.append(cell)
            }
        }

        for (dx, dy) in GridCoord.cardinals {
            consider(seed.neighbor(dx: dx, dy: dy))
        }
        frontier.sort { ($0.x, $0.y) < ($1.x, $1.y) }

        while area.count < targetCount, !frontier.isEmpty {
            guard let pick = rng.pick(frontier) else { break }
            frontier.removeAll { $0 == pick }
            area.append(pick)
            inArea.insert(pick)
            for (dx, dy) in GridCoord.cardinals {
                consider(pick.neighbor(dx: dx, dy: dy))
            }
            frontier.sort { ($0.x, $0.y) < ($1.x, $1.y) }
        }
        return area
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

    /// Converts tracked door openings into gate strips with `chance` per door.
    /// Gates are exactly two adjacent tiles with rooms on both sides (never corner walls).
    /// At most one gate per shared wall between any two rooms.
    private func placeGatesOnDoorOpenings(
        _ openings: [DoorOpening],
        rooms: [GeneratedRoom],
        tiles: inout [[[Tile]]],
        story: Int,
        chance: Double,
        rng: inout SeededGenerator
    ) {
        let roomByCell: [GridCoord: Int] = rooms.reduce(into: [:]) { map, room in
            for cell in room.cells {
                map[cell] = room.id
            }
        }
        let roomsByID = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        let roomCells = rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }
        let ordered = openings.sorted { lhs, rhs in
            let a = lhs.cells.first ?? GridCoord(x: 0, y: 0, story: story)
            let b = rhs.cells.first ?? GridCoord(x: 0, y: 0, story: story)
            if a.x != b.x { return a.x < b.x }
            if a.y != b.y { return a.y < b.y }
            return lhs.cells.count < rhs.cells.count
        }
        var gatedPairs = Set<RoomPair>()
        for opening in ordered {
            let openCells = opening.cells.filter { cell in
                guard cell.y >= 0, cell.y < tiles[story].count else { return false }
                guard cell.x >= 0, cell.x < tiles[story][cell.y].count else { return false }
                return isFloor(tiles[story][cell.y][cell.x]) || tiles[story][cell.y][cell.x].isGate
            }
            // Only true room–room partition cells (excludes corner walls).
            guard let gateCells = contiguousRoomPartitionPair(
                from: openCells,
                roomByCell: roomByCell
            ) else { continue }
            guard let pair = roomPartitionInfo(gateCells[0], roomByCell: roomByCell)?.pair else { continue }
            // Never more than one gate on the same wall between two rooms.
            guard !gatedPairs.contains(pair) else { continue }
            // No gate if the rooms already connect through a hallway (ignore this opening).
            guard !roomsConnectedViaHallway(
                pair: pair,
                roomsByID: roomsByID,
                roomByCell: roomByCell,
                roomCells: roomCells,
                tiles: tiles[story],
                treatingAsBlocked: Set(gateCells)
            ) else { continue }
            guard rng.nextBool(probability: chance) else { continue }
            for cell in gateCells {
                tiles[story][cell.y][cell.x] = Tile(kind: .gate)
            }
            gatedPairs.insert(pair)
        }
    }

    /// Two orthogonally adjacent cells that each separate the same two rooms (not corners).
    private func contiguousRoomPartitionPair(
        from cells: [GridCoord],
        roomByCell: [GridCoord: Int]
    ) -> [GridCoord]? {
        let partitions = cells.compactMap { cell -> (GridCoord, RoomPair)? in
            guard let info = roomPartitionInfo(cell, roomByCell: roomByCell) else { return nil }
            return (cell, info.pair)
        }
        guard partitions.count >= 2 else { return nil }

        let ordered = partitions.sorted { ($0.0.x, $0.0.y) < ($1.0.x, $1.0.y) }
        for i in 0..<ordered.count {
            for j in (i + 1)..<ordered.count {
                let a = ordered[i]
                let b = ordered[j]
                guard a.1 == b.1 else { continue }
                let dist = abs(a.0.x - b.0.x) + abs(a.0.y - b.0.y)
                guard dist == 1 else { continue }
                return [a.0, b.0]
            }
        }
        return nil
    }

    /// Soft walls: exactly two adjacent true room–room partition tiles, flanked by
    /// solid walls on both ends along the wall (never corners / opening edges).
    /// At most one soft blocker (gate or destructible wall) per shared wall between rooms.
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
        let roomsByID = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        let roomCells = rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }
        // Pairs that already have a gate — no soft wall on that same shared wall.
        var occupiedPairs = roomPairsSeparatedByGate(in: story, roomByCell: roomByCell)
        let candidates = destructibleWallSegments(in: story, roomByCell: roomByCell)

        var claimed = Set<GridCoord>()
        for segment in candidates {
            guard segment.count == 2 else { continue }
            guard segment.allSatisfy({ !claimed.contains($0) }) else { continue }
            guard let first = segment.first,
                  let info = roomPartitionInfo(first, roomByCell: roomByCell),
                  !occupiedPairs.contains(info.pair)
            else { continue }
            // Keep soft-wall groups at most 2 tiles: never abut an already-placed soft wall.
            let touchesExisting = segment.contains { cell in
                GridCoord.cardinals.contains { dx, dy in
                    claimed.contains(cell.neighbor(dx: dx, dy: dy))
                }
            }
            guard !touchesExisting else { continue }
            // Defense in depth: never place next to a gate tile either.
            guard !segmentAbutsGate(segment, in: story) else { continue }
            // Both cells must be sealed room–room partitions for the same pair.
            guard isSealedPathSegment(segment, in: story, roomByCell: roomByCell) else { continue }
            // Solid wall tiles must flank both ends along the wall (not a corner/edge opening).
            guard segmentHasSolidWallFlanks(
                segment,
                alongDX: info.alongDX,
                alongDY: info.alongDY,
                in: story
            ) else { continue }
            // No soft wall if the rooms already connect through a hallway.
            guard !roomsConnectedViaHallway(
                pair: info.pair,
                roomsByID: roomsByID,
                roomByCell: roomByCell,
                roomCells: roomCells,
                tiles: story
            ) else { continue }
            guard rng.nextBool(probability: chance) else { continue }
            for cell in segment {
                story[cell.y][cell.x] = Tile(kind: .wall(destructible: true))
                claimed.insert(cell)
            }
            // At most one destructible wall on this shared wall.
            occupiedPairs.insert(info.pair)
        }
    }

    /// True when the two rooms can reach each other on a floor/gate path that uses a hallway
    /// (a non-room cell that is not itself a room–room door/partition opening).
    private func roomsConnectedViaHallway(
        pair: RoomPair,
        roomsByID: [Int: GeneratedRoom],
        roomByCell: [GridCoord: Int],
        roomCells: Set<GridCoord>,
        tiles: [[Tile]],
        treatingAsBlocked: Set<GridCoord> = []
    ) -> Bool {
        guard let roomA = roomsByID[pair.low], let roomB = roomsByID[pair.high] else { return false }
        let targets = roomB.cells
        var queue: [(GridCoord, Bool)] = roomA.cells.map { ($0, false) }
        var visited: Set<GridCoord> = roomA.cells
        var head = 0

        while head < queue.count {
            let (current, sawHallway) = queue[head]
            head += 1
            if sawHallway, targets.contains(current) { return true }

            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard !visited.contains(next) else { continue }
                guard next.y >= 0, next.y < tiles.count else { continue }
                guard next.x >= 0, next.x < tiles[next.y].count else { continue }
                guard !treatingAsBlocked.contains(next) else { continue }
                let tile = tiles[next.y][next.x]
                let passable = isFloor(tile) || tile.isGate
                guard passable else { continue }

                let nextSawHallway = sawHallway || isHallwayCell(
                    next,
                    roomCells: roomCells,
                    roomByCell: roomByCell
                )
                visited.insert(next)
                queue.append((next, nextSawHallway))
            }
        }
        return false
    }

    /// Corridor cell: outside every room and not a direct room–room partition opening.
    private func isHallwayCell(
        _ cell: GridCoord,
        roomCells: Set<GridCoord>,
        roomByCell: [GridCoord: Int]
    ) -> Bool {
        guard !roomCells.contains(cell) else { return false }
        return roomPartitionInfo(cell, roomByCell: roomByCell) == nil
    }

    /// True when the cells immediately before/after the segment along the wall are solid walls.
    private func segmentHasSolidWallFlanks(
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
        return isSolidNonDestructibleWall(before, in: story)
            && isSolidNonDestructibleWall(after, in: story)
    }

    private func isSolidNonDestructibleWall(_ coord: GridCoord, in story: [[Tile]]) -> Bool {
        guard coord.y >= 0, coord.y < story.count else { return false }
        guard coord.x >= 0, coord.x < story[coord.y].count else { return false }
        if case .wall(false) = story[coord.y][coord.x].kind { return true }
        return false
    }

    private func roomPairForOpening(
        _ cells: [GridCoord],
        roomByCell: [GridCoord: Int]
    ) -> RoomPair? {
        for cell in cells {
            for (dx, dy) in GridCoord.cardinals {
                let a = cell.neighbor(dx: dx, dy: dy)
                let b = cell.neighbor(dx: -dx, dy: -dy)
                guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
                return RoomPair(idA, idB)
            }
        }
        return nil
    }

    /// Room pairs that already have a gate opening between them on their shared wall.
    private func roomPairsSeparatedByGate(
        in story: [[Tile]],
        roomByCell: [GridCoord: Int]
    ) -> Set<RoomPair> {
        var pairs = Set<RoomPair>()
        for y in 0..<story.count {
            for x in 0..<story[y].count {
                guard story[y][x].isGate else { continue }
                let coord = GridCoord(x: x, y: y, story: 0)
                for (dx, dy) in GridCoord.cardinals {
                    let a = coord.neighbor(dx: dx, dy: dy)
                    let b = coord.neighbor(dx: -dx, dy: -dy)
                    guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
                    pairs.insert(RoomPair(idA, idB))
                }
            }
        }
        return pairs
    }

    private func segmentAbutsGate(_ segment: [GridCoord], in story: [[Tile]]) -> Bool {
        for cell in segment {
            for (dx, dy) in GridCoord.cardinals {
                let next = cell.neighbor(dx: dx, dy: dy)
                guard next.y >= 0, next.y < story.count else { continue }
                guard next.x >= 0, next.x < story[next.y].count else { continue }
                if story[next.y][next.x].isGate { return true }
            }
        }
        return false
    }

    /// True when every cell is a solid wall between the same room pair (sealed shortcut).
    private func isSealedPathSegment(
        _ segment: [GridCoord],
        in story: [[Tile]],
        roomByCell: [GridCoord: Int]
    ) -> Bool {
        guard let first = segment.first,
              let info = roomPartitionInfo(first, roomByCell: roomByCell)
        else { return false }

        for cell in segment {
            guard case .wall(false) = story[cell.y][cell.x].kind else { return false }
            guard let cellInfo = roomPartitionInfo(cell, roomByCell: roomByCell),
                  cellInfo.pair == info.pair
            else { return false }
        }
        return true
    }

    /// Candidate 2-tile solid-wall segments between distinct rooms (no singles / corners).
    private func destructibleWallSegments(
        in story: [[Tile]],
        roomByCell: [GridCoord: Int]
    ) -> [[GridCoord]] {
        var partitionCells: [(GridCoord, RoomPair, Int, Int)] = []
        for y in 0..<story.count {
            for x in 0..<story[y].count {
                guard case .wall(false) = story[y][x].kind else { continue }
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
               case .wall(false) = story[next.y][next.x].kind,
               !used.contains(next) {
                let segment = [coord, next].sorted { ($0.x, $0.y) < ($1.x, $1.y) }
                segments.append(segment)
                used.formUnion(segment)
                continue
            }

            let prev = coord.neighbor(dx: -alongDX, dy: -alongDY)
            if let prevInfo = roomPartitionInfo(prev, roomByCell: roomByCell),
               prevInfo.pair == pair,
               case .wall(false) = story[prev.y][prev.x].kind,
               !used.contains(prev) {
                let segment = [prev, coord].sorted { ($0.x, $0.y) < ($1.x, $1.y) }
                segments.append(segment)
                used.formUnion(segment)
                continue
            }
            // Single partition cells / corners are not valid destructible walls.
        }

        return segments.sorted { lhs, rhs in
            let a = lhs[0]
            let b = rhs[0]
            if a.x != b.x { return a.x < b.x }
            return a.y < b.y
        }
    }

    private struct RoomPair: Hashable {
        let low: Int
        let high: Int
        init(_ a: Int, _ b: Int) {
            low = min(a, b)
            high = max(a, b)
        }
    }

    private func roomPartitionInfo(
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
