import Foundation

nonisolated struct ProceduralGenerator: Sendable {
    /// How many seed offsets to try when a layout cannot host every required interactable.
    private static let maxValidityAttempts = 48

    func generate(
        from app: AppConfig,
        level: LevelConfig,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback,
        floorTileSet: FloorTileSet? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) throws -> GameWorld {
        try generate(
            from: .compose(app: app, level: level),
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            floorTileSet: floorTileSet,
            onProgress: onProgress
        )
    }

    func generate(
        from config: WorldGenerationConfig,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback,
        floorTileSet: FloorTileSet? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) throws -> GameWorld {
        try generateDetailed(
            from: config,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            floorTileSet: floorTileSet,
            onProgress: onProgress
        ).world
    }

    func generateDetailed(
        from app: AppConfig,
        level: LevelConfig,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback,
        floorTileSet: FloorTileSet? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) throws -> GenerationResult {
        try generateDetailed(
            from: .compose(app: app, level: level),
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            floorTileSet: floorTileSet,
            onProgress: onProgress
        )
    }

    func generateDetailed(
        from config: WorldGenerationConfig,
        playerConfig: PlayerConfig = .fallback,
        enemyConfig: EnemyConfig = .fallback,
        floorTileSet: FloorTileSet? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) throws -> GenerationResult {
        try config.validate()
        try playerConfig.validate()
        let resolvedFloorSet = try floorTileSet ?? FloorTileSet.loadFromBundle(set: config.floorSet)

        let baseSeed = config.resolvedSeed()
        var lastMissing: [RequiredInteractable] = RequiredInteractable.allCases
        var peakProgress = 0.0

        func report(_ value: Double) {
            peakProgress = max(peakProgress, min(1, max(0, value)))
            onProgress?(peakProgress)
        }

        for attempt in 0..<Self.maxValidityAttempts {
            let seed = baseSeed &+ UInt64(attempt)
            let result = try generateAttempt(
                seed: seed,
                config: config,
                playerConfig: playerConfig,
                enemyConfig: enemyConfig,
                floorTileSet: resolvedFloorSet,
                onPhaseProgress: { phaseFraction in
                    // Keep retries monotonic: each attempt advances a shrinking remainder.
                    let attemptBase = 1 - pow(0.55, Double(attempt))
                    let attemptSpan = pow(0.55, Double(attempt)) * 0.92
                    report(attemptBase + attemptSpan * phaseFraction)
                }
            )
            let storyTiles = result.world.tiles.first ?? []
            let missing = Self.missingRequiredInteractables(in: result.world)
            let passagesGated = Self.roomsAreSeparatedByGates(
                rooms: result.rooms,
                tiles: storyTiles
            )
            let gateConnected = Self.allRoomsGateConnected(
                rooms: result.rooms,
                spawn: result.world.spawn,
                tiles: storyTiles
            )
            if missing.isEmpty, passagesGated, gateConnected {
                report(1)
                return result
            }
            // Connectivity failures may leave interactables present — keep a useful error reason.
            if missing.isEmpty, !passagesGated || !gateConnected {
                lastMissing = [.gate]
            } else {
                lastMissing = missing
            }
            report(1 - pow(0.55, Double(attempt + 1)))
        }

        throw WorldSeedError.missingRequiredInteractables(lastMissing)
    }

    private func generateAttempt(
        seed: UInt64,
        config: WorldGenerationConfig,
        playerConfig: PlayerConfig,
        enemyConfig: EnemyConfig,
        floorTileSet: FloorTileSet,
        onPhaseProgress: ((Double) -> Void)? = nil
    ) throws -> GenerationResult {
        let phaseCount = 5.0
        func phase(_ index: Double) {
            onPhaseProgress?(min(1, index / phaseCount))
        }

        var rng = SeededGenerator(seed: seed)
        let width = config.world.width
        let height = config.world.height
        let stories = config.world.stories
        let params = config.generation

        var tiles = filledWalls(width: width, height: height, stories: stories)

        let rooms = placePackedRooms(
            count: params.roomCount,
            minSize: params.room.minRoomSize,
            maxSize: params.room.maxRoomSize,
            width: width,
            height: height,
            rng: &rng
        )

        carveRooms(rooms, into: &tiles[0])
        phase(1)

        let roomByCell: [GridCoord: Int] = rooms.reduce(into: [:]) { map, room in
            for cell in room.cells {
                map[cell] = room.id
            }
        }
        let segmentsByPair = sharedWallSegmentsByPair(in: tiles[0], roomByCell: roomByCell)
        let joinEdges = adjacencySpanningTree(rooms: rooms, segmentsByPair: segmentsByPair)

        let topRight = topRightRoom(from: rooms)
        let spawn = spawnCell(for: topRight)

        // Gate every join in the shared wall, repair connectivity, then optional shortcuts.
        placeJoinGates(
            joinEdges,
            segmentsByPair: segmentsByPair,
            tiles: &tiles,
            story: 0,
            gateMinigameKinds: config.gateMinigameKinds,
            rng: &rng
        )
        ensureGateConnectivity(
            rooms: rooms,
            spawn: spawn,
            segmentsByPair: segmentsByPair,
            tiles: &tiles,
            story: 0,
            gateMinigameKinds: config.gateMinigameKinds,
            rng: &rng
        )
        placePartitionGates(
            rooms: rooms,
            in: &tiles[0],
            chance: params.room.partitionGateChance,
            gateMinigameKinds: config.gateMinigameKinds,
            rng: &rng
        )
        phase(2)

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
        phase(3)

        let letter = playerConfig.letter.first ?? "P"
        let player = GameEntity(letter: letter, position: spawn, isPlayer: true)
        var entities = [player]
        var occupied: Set<GridCoord> = [spawn]

        if let spawnConfig = config.enemies {
            let resolvedTypes: [(id: String, config: EnemyTypeConfig)] = spawnConfig.types.compactMap { id in
                guard let typeConfig = enemyConfig.type(named: id) else { return nil }
                return (id, typeConfig)
            }
            if !resolvedTypes.isEmpty {
                let enemies = spawnEnemies(
                    in: rooms,
                    excludingRoomID: topRight.id,
                    tiles: tiles,
                    types: resolvedTypes,
                    chance: spawnConfig.spawnChancePerRoom,
                    occupied: &occupied,
                    rng: &rng
                )
                entities.append(contentsOf: enemies)
            }
        }

        // Pickup cells only — used so health/energy/treasure never sit on adjacent tiles.
        var pickupCells: Set<GridCoord> = []

        if let pickups = config.pickups {
            let spawned = spawnPickups(
                pickups,
                in: rooms,
                excludingRoomID: topRight.id,
                tiles: tiles,
                occupied: &occupied,
                pickupCells: &pickupCells,
                rng: &rng
            )
            entities.append(contentsOf: spawned)
        }

        if let treasure = spawnTreasure(
            in: rooms,
            spawn: spawn,
            tiles: tiles,
            occupied: &occupied,
            pickupCells: &pickupCells,
            rng: &rng
        ) {
            entities.append(treasure)
        }
        phase(4)

        // Guarantee at least one of each interactable when the rolls/layout allow it.
        ensureRequiredInteractables(
            rooms: rooms,
            excludingRoomID: topRight.id,
            spawn: spawn,
            tiles: &tiles,
            entities: &entities,
            occupied: &occupied,
            config: config,
            enemyConfig: enemyConfig,
            rng: &rng
        )

        var floorRng = SeededGenerator(seed: seed ^ FloorTiler.seedSalt)
        for storyIndex in tiles.indices {
            FloorTiler.tile(
                tiles: &tiles[storyIndex],
                story: storyIndex,
                set: floorTileSet,
                options: FloorTiler.Options(decorProb: config.decorProb),
                rng: &floorRng
            )
        }
        phase(5)

        let world = GameWorld(
            width: width,
            height: height,
            storyCount: stories,
            tiles: tiles,
            entities: entities,
            spawn: spawn,
            healthCount: playerConfig.startingHealth,
            energyCount: playerConfig.startingEnergy,
            floorSet: floorTileSet,
            decorProb: config.decorProb,
            tileSeed: seed ^ FloorTiler.seedSalt
        )

        return GenerationResult(
            world: world,
            rooms: rooms,
            topRightRoomID: topRight.id,
            joinPairs: joinEdges
        )
    }
    /// Force-places any missing required interactables (chance rolls already applied).
    private func ensureRequiredInteractables(
        rooms: [GeneratedRoom],
        excludingRoomID: Int,
        spawn: GridCoord,
        tiles: inout [[[Tile]]],
        entities: inout [GameEntity],
        occupied: inout Set<GridCoord>,
        config: WorldGenerationConfig,
        enemyConfig: EnemyConfig,
        rng: inout SeededGenerator
    ) {
        let missing = Self.missingRequiredInteractables(tiles: tiles, entities: entities)
        guard !missing.isEmpty else { return }

        if missing.contains(.gate) {
            forceOnePartitionGate(
                rooms: rooms,
                in: &tiles[0],
                gateMinigameKinds: config.gateMinigameKinds,
                rng: &rng
            )
        }

        if missing.contains(.pit) {
            forceOnePit(
                rooms: rooms,
                into: &tiles[0],
                meanSize: config.generation.room.pitMeanSize,
                maxSize: config.generation.room.pitMaxSize,
                excludingRoomID: excludingRoomID,
                excluding: occupied.union([spawn]),
                rng: &rng
            )
            clearPits(around: spawn, tiles: &tiles, story: 0)
        }

        if missing.contains(.enemy) {
            if let enemy = forceOneEnemy(
                in: rooms,
                excludingRoomID: excludingRoomID,
                tiles: tiles,
                config: config,
                enemyConfig: enemyConfig,
                occupied: &occupied,
                rng: &rng
            ) {
                entities.append(enemy)
            }
        }
    }

    /// Places exactly one 2-tile partition gate on the first valid sealed segment.
    @discardableResult
    private func forceOnePartitionGate(
        rooms: [GeneratedRoom],
        in story: inout [[Tile]],
        gateMinigameKinds: [GateMinigameKind],
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

            let kind = pickGateMinigameKind(from: gateMinigameKinds, rng: &rng)
            for cell in segment {
                story[cell.y][cell.x] = Tile(kind: .gate(minigame: kind))
            }
            return true
        }
        return false
    }

    /// Places a single pit blob in the first eligible non-spawn room.
    @discardableResult
    private func forceOnePit(
        rooms: [GeneratedRoom],
        into story: inout [[Tile]],
        meanSize: Double,
        maxSize: Int,
        excludingRoomID: Int,
        excluding blocked: Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> Bool {
        let ordered = rooms.sorted { $0.id < $1.id }
        for room in ordered where room.id != excludingRoomID {
            let candidates = room.cells
                .filter { cell in
                    guard !blocked.contains(cell) else { return false }
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
                excluding: blocked,
                in: story,
                rng: &rng
            )
            for cell in area {
                story[cell.y][cell.x] = Tile(kind: .floor(isPit: true))
            }
            return !area.isEmpty
        }
        return false
    }

    /// Places a single enemy when the probabilistic pass produced none.
    private func forceOneEnemy(
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        config: WorldGenerationConfig,
        enemyConfig: EnemyConfig,
        occupied: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GameEntity? {
        let resolvedTypes: [(id: String, config: EnemyTypeConfig)]
        if let spawnConfig = config.enemies {
            let fromConfig: [(id: String, config: EnemyTypeConfig)] = spawnConfig.types.compactMap { id in
                guard let configured = enemyConfig.type(named: id) else { return nil }
                return (id, configured)
            }
            if !fromConfig.isEmpty {
                resolvedTypes = fromConfig
            } else if let first = enemyConfig.enemies.sorted(by: { $0.key < $1.key }).first {
                resolvedTypes = [(first.key, first.value)]
            } else {
                return nil
            }
        } else if let first = enemyConfig.enemies.sorted(by: { $0.key < $1.key }).first {
            resolvedTypes = [(first.key, first.value)]
        } else {
            return nil
        }

        let ordered = rooms.sorted { $0.id < $1.id }
        for room in ordered where room.id != excludingRoomID {
            guard let position = pickRoomFloorCell(
                in: room,
                tiles: tiles,
                occupied: occupied,
                rng: &rng
            ) else { continue }

            let pick = Self.pickEnemyType(from: resolvedTypes, rng: &rng)
            occupied.insert(position)
            return GameEntity(
                letter: pick.config.letterCharacter,
                position: position,
                isPlayer: false,
                enemyTypeID: pick.id
            )
        }
        return nil
    }

    /// One roll per room (except the spawn room); place on a room floor cell only.
    /// When multiple types are configured, each spawn picks uniformly among them.
    private func spawnEnemies(
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        types: [(id: String, config: EnemyTypeConfig)],
        chance: Double,
        occupied: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> [GameEntity] {
        var enemies: [GameEntity] = []
        guard !types.isEmpty else { return enemies }

        for room in rooms where room.id != excludingRoomID {
            guard rng.nextBool(probability: chance) else { continue }
            guard let position = pickRoomFloorCell(
                in: room,
                tiles: tiles,
                occupied: occupied,
                rng: &rng
            ) else { continue }

            let pick = Self.pickEnemyType(from: types, rng: &rng)
            occupied.insert(position)
            enemies.append(
                GameEntity(
                    letter: pick.config.letterCharacter,
                    position: position,
                    isPlayer: false,
                    enemyTypeID: pick.id
                )
            )
        }

        return enemies
    }

    /// Single-type lists skip the RNG draw so spawn streams stay stable vs legacy `type:`.
    private static func pickEnemyType(
        from types: [(id: String, config: EnemyTypeConfig)],
        rng: inout SeededGenerator
    ) -> (id: String, config: EnemyTypeConfig) {
        if types.count == 1 {
            return types[0]
        }
        return types[rng.nextInt(upperBound: types.count)]
    }

    /// One roll per room per kind (except the spawn room); visible room floor only.
    ///
    /// Never places two pickups on the same or orthogonally adjacent tiles.
    private func spawnPickups(
        _ config: LevelConfig.PickupsSpawnConfig,
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        pickupCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> [GameEntity] {
        var pickups: [GameEntity] = []
        var kinds: [(PickupKind, Double?)] = [
            (.health, config.health?.spawnChancePerRoom),
        ]
        if EnergyMechanic.isEnabled {
            kinds.append((.energy, config.energy?.spawnChancePerRoom))
        }

        for (kind, chance) in kinds {
            guard let chance else { continue }
            for room in rooms where room.id != excludingRoomID {
                guard rng.nextBool(probability: chance) else { continue }
                guard let position = pickVisiblePickupFloorCell(
                    in: room,
                    tiles: tiles,
                    occupied: occupied,
                    pickupCells: pickupCells,
                    rng: &rng
                ) else { continue }

                occupied.insert(position)
                pickupCells.insert(position)
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

    /// Places exactly one treasure on a visible floor tile in the farthest room that has one.
    private func spawnTreasure(
        in rooms: [GeneratedRoom],
        spawn: GridCoord,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        pickupCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GameEntity? {
        let ordered = rooms.sorted { lhs, rhs in
            let lhsDist = manhattan(spawn, lhs.center)
            let rhsDist = manhattan(spawn, rhs.center)
            if lhsDist != rhsDist { return lhsDist > rhsDist }
            return lhs.id > rhs.id
        }

        for room in ordered {
            guard let position = pickVisiblePickupFloorCell(
                in: room,
                tiles: tiles,
                occupied: occupied,
                pickupCells: pickupCells,
                rng: &rng
            ) else { continue }

            occupied.insert(position)
            pickupCells.insert(position)
            return GameEntity(
                letter: " ",
                position: position,
                isPlayer: false,
                pickupKind: .treasure
            )
        }
        return nil
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

    /// Picks a cell for enemies: room floor only (never pit, gate, wall, or hallway).
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

    /// Picks a pickup cell in full view and at least one tile from any wall/gate.
    ///
    /// Also skips cells that share an edge with an already-placed pickup.
    private func pickVisiblePickupFloorCell(
        in room: GeneratedRoom,
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>,
        pickupCells: Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GridCoord? {
        let candidates = room.cells
            .filter { cell in
                guard !occupied.contains(cell) else { return false }
                guard !isOrthogonallyAdjacent(cell, toAnyIn: pickupCells) else { return false }
                guard isEntityPlaceableRoomFloor(cell, in: room, tiles: tiles) else { return false }
                return !IsometricTileGeometry.isAdjacentToOpaqueOccluder(at: cell, in: tiles[0])
            }
            .sorted { lhs, rhs in
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.y < rhs.y
            }
        return rng.pick(candidates)
    }

    /// True when `cell` shares an edge with any coord in `others` (same story).
    private func isOrthogonallyAdjacent(_ cell: GridCoord, toAnyIn others: Set<GridCoord>) -> Bool {
        for (dx, dy) in GridCoord.cardinals {
            if others.contains(cell.neighbor(dx: dx, dy: dy)) {
                return true
            }
        }
        return false
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
        case .gate(_), .wall:
            return false
        }
    }
    // MARK: - Packed adjacency joins

    /// Gate-ready 2-cell wall segments grouped by the room pair they separate.
    private func sharedWallSegmentsByPair(
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
    private func adjacencySpanningTree(
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

    /// Writes one 2-cell gate strip into the shared wall of each join, no carving.
    @discardableResult
    private func placeJoinGates(
        _ edges: [(Int, Int)],
        segmentsByPair: [RoomPair: [[GridCoord]]],
        tiles: inout [[[Tile]]],
        story: Int,
        gateMinigameKinds: [GateMinigameKind],
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
            let kind = pickGateMinigameKind(from: gateMinigameKinds, rng: &rng)
            for cell in segment {
                tiles[story][cell.y][cell.x] = Tile(kind: .gate(minigame: kind))
            }
            placed += 1
        }
        return placed
    }


    // MARK: - Reachability repair

    /// Gates an unused shared wall when a room is not yet reachable through gates.
    @discardableResult
    private func ensureGateConnectivity(
        rooms: [GeneratedRoom],
        spawn: GridCoord,
        segmentsByPair: [RoomPair: [[GridCoord]]],
        tiles: inout [[[Tile]]],
        story: Int,
        gateMinigameKinds: [GateMinigameKind],
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
                        gateMinigameKinds: gateMinigameKinds,
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
                excluding: [spawn],
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
        excluding blocked: Set<GridCoord>,
        in story: [[Tile]],
        rng: inout SeededGenerator
    ) -> [GridCoord] {
        var area = [seed]
        var inArea: Set<GridCoord> = [seed]
        var frontier: [GridCoord] = []

        func consider(_ cell: GridCoord) {
            guard roomCells.contains(cell), !blocked.contains(cell), !inArea.contains(cell) else { return }
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

    /// Optional sealed shared-wall shortcut gates: exactly two adjacent room–room partition
    /// tiles, flanked by solid walls (never corners / opening edges).
    /// At most one gate feature per shared wall between rooms (joins already gated).
    private func placePartitionGates(
        rooms: [GeneratedRoom],
        in story: inout [[Tile]],
        chance: Double,
        gateMinigameKinds: [GateMinigameKind],
        rng: inout SeededGenerator
    ) {
        let roomByCell: [GridCoord: Int] = rooms.reduce(into: [:]) { map, room in
            for cell in room.cells {
                map[cell] = room.id
            }
        }
        var occupiedPairs = roomPairsSeparatedByGate(in: story, roomByCell: roomByCell)
        let candidates = partitionGateSegments(in: story, roomByCell: roomByCell)

        var claimed = Set<GridCoord>()
        for segment in candidates {
            guard segment.count == 2 else { continue }
            guard segment.allSatisfy({ !claimed.contains($0) }) else { continue }
            guard let first = segment.first,
                  let info = roomPartitionInfo(first, roomByCell: roomByCell),
                  !occupiedPairs.contains(info.pair)
            else { continue }
            let touchesExisting = segment.contains { cell in
                GridCoord.cardinals.contains { dx, dy in
                    claimed.contains(cell.neighbor(dx: dx, dy: dy))
                }
            }
            guard !touchesExisting else { continue }
            guard !segmentAbutsGate(segment, in: story) else { continue }
            guard isSealedPathSegment(segment, in: story, roomByCell: roomByCell) else { continue }
            guard segmentHasSolidWallFlanks(
                segment,
                alongDX: info.alongDX,
                alongDY: info.alongDY,
                in: story
            ) else { continue }
            guard rng.nextBool(probability: chance) else { continue }
            let kind = pickGateMinigameKind(from: gateMinigameKinds, rng: &rng)
            for cell in segment {
                story[cell.y][cell.x] = Tile(kind: .gate(minigame: kind))
                claimed.insert(cell)
            }
            occupiedPairs.insert(info.pair)
        }
    }

    private func pickGateMinigameKind(
        from kinds: [GateMinigameKind],
        rng: inout SeededGenerator
    ) -> GateMinigameKind {
        let pool = kinds.isEmpty ? [GateMinigameKind.spelling] : kinds
        return pool[Int.random(in: 0..<pool.count, using: &rng)]
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
        return isSolidWall(before, in: story)
            && isSolidWall(after, in: story)
    }

    private func isSolidWall(_ coord: GridCoord, in story: [[Tile]]) -> Bool {
        guard coord.y >= 0, coord.y < story.count else { return false }
        guard coord.x >= 0, coord.x < story[coord.y].count else { return false }
        if case .wall = story[coord.y][coord.x].kind { return true }
        return false
    }

    /// Room pairs that already have a gate on their join (shared-wall partition).
    private func roomPairsSeparatedByGate(
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

    private func segmentAbutsGate(_ segment: [GridCoord], in story: [[Tile]]) -> Bool {
        abuttingGateKind(segment, in: story) != nil
    }

    private func abuttingGateKind(_ segment: [GridCoord], in story: [[Tile]]) -> GateMinigameKind? {
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
    private func isSealedPathSegment(
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
    private func partitionGateSegments(
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

    /// Generation reachability treats gates as passable (walls block).
    private func isGenerationPassable(_ tile: Tile) -> Bool {
        switch tile.kind {
        case .floor(_), .gate(_):
            return true
        case .wall:
            return false
        }
    }
}
