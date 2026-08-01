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
        let phaseCount = Double(GenerationPass.allCases.count)
        var state = GenerationAttemptState(
            rng: SeededGenerator(seed: seed),
            tiles: [],
            rooms: [],
            entities: [],
            occupied: [],
            pickupCells: [],
            spawn: GridCoord(x: 0, y: 0, story: 0),
            topRight: GeneratedRoom(id: 0, cells: [], center: GridCoord(x: 0, y: 0, story: 0), latticeX: 0, latticeY: 0),
            joinEdges: [],
            width: config.world.width,
            height: config.world.height,
            stories: config.world.stories
        )

        for pass in GenerationPass.allCases {
            runGenerationPass(
                pass,
                state: &state,
                config: config,
                playerConfig: playerConfig,
                enemyConfig: enemyConfig,
                floorTileSet: floorTileSet,
                seed: seed
            )
            onPhaseProgress?(min(1, pass.phaseIndex / phaseCount))
        }

        let world = GameWorld(
            width: state.width,
            height: state.height,
            storyCount: state.stories,
            tiles: state.tiles,
            entities: state.entities,
            spawn: state.spawn,
            healthCount: playerConfig.startingHealth,
            energyCount: playerConfig.startingEnergy,
            floorSet: floorTileSet,
            decorProb: config.decorProb,
            tileSeed: seed ^ FloorTiler.seedSalt
        )

        return GenerationResult(
            world: world,
            rooms: state.rooms,
            topRightRoomID: state.topRight.id,
            joinPairs: state.joinEdges
        )
    }
}
