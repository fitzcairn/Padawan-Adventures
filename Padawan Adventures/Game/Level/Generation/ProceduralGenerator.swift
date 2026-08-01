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
}
