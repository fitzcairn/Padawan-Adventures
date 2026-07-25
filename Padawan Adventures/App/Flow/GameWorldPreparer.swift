import Foundation

enum GameWorldPreparer {
    @MainActor
    static func prepareLaunch(session: AppSession, mode: GameLaunchMode) async -> GameWorld {
        if mode == .continueSave, let lastLevel = session.playerState?.lastLevelStarted {
            try? session.selectLevel(resourceName: lastLevel)
        }

        if let resourceName = session.selectedLevelResourceName {
            if mode == .newGame {
                await session.resetLevelStarsCurrent(resourceName: resourceName)
            }
            await session.markLevelStarted(resourceName: resourceName)
        }

        // Warm sprite cache once per session before the world is presented.
        session.ensurePlayerSpritesLoaded()
        session.ensureItemSpritesLoaded()

        var world = await loadWorld(session: session, mode: mode)
        // TEST: stamp sand onto every floor tile.
        paintUniformFloorSprites(on: &world, terrainID: "sand", library: session.floorSpriteLibrary)
        return world
    }

    @MainActor
    static func loadWorld(session: AppSession, mode: GameLaunchMode) async -> GameWorld {
        switch mode {
        case .continueSave:
            if let saved = try? await session.saveService.load(),
               WorldLoader.isCompatibleSave(saved, with: session.seedConfig) {
                return saved
            }
            return await generateWorld(session: session)

        case .newGame:
            try? await session.saveService.delete()
            await session.resetVitalsToStarting()
            return await generateWorld(session: session)
        }
    }

    /// Assigns a single terrain id to every floor cell (visibility / layout testing).
    @MainActor
    static func paintUniformFloorSprites(
        on world: inout GameWorld,
        terrainID: String,
        library: FloorSpriteLibrary
    ) {
        guard library.animation(id: terrainID) != nil else {
            print("FloorSpriteLibrary missing \"\(terrainID)\" — cannot paint uniform floor sprites")
            return
        }
        for story in 0..<world.storyCount {
            for y in 0..<world.height {
                for x in 0..<world.width {
                    let coord = GridCoord(x: x, y: y, story: story)
                    guard case .floor(let isPit) = world.tile(at: coord)?.kind else { continue }
                    world.setTile(Tile(kind: .floor(isPit: isPit), terrainID: terrainID), at: coord)
                }
            }
        }
    }

    @MainActor
    private static func generateWorld(session: AppSession) async -> GameWorld {
        var config = session.seedConfig
        let playerConfig = session.playerConfig
        let enemyConfig = session.enemyConfig
        let health = session.playerState?.health ?? playerConfig.startingHealth
        let energy = session.playerState?.energy ?? playerConfig.startingEnergy

        // TEST: every floor uses sand.
        config.floorSprites = ["sand"]

        let terrainNearby = session.terrainCatalog.nearbyByID
        do {
            var world = try await Task.detached(priority: .userInitiated) {
                try ProceduralGenerator().generate(
                    from: config,
                    playerConfig: playerConfig,
                    enemyConfig: enemyConfig,
                    terrainNearby: terrainNearby
                )
            }.value
            world.healthCount = health
            world.energyCount = energy
            return world
        } catch {
            let fallback = AppSession.fallbackConfig()
            do {
                var world = try await Task.detached(priority: .userInitiated) {
                    try ProceduralGenerator().generate(
                        from: fallback,
                        playerConfig: .fallback,
                        enemyConfig: .fallback,
                        terrainNearby: terrainNearby
                    )
                }.value
                world.healthCount = health
                world.energyCount = energy
                return world
            } catch {
                return minimalWorld(health: health, energy: energy, playerConfig: playerConfig)
            }
        }
    }

    private static func minimalWorld(
        health: Int,
        energy: Int,
        playerConfig: PlayerConfig
    ) -> GameWorld {
        GameWorld(
            width: 1,
            height: 1,
            storyCount: 1,
            tiles: [[[Tile(kind: .floor(isPit: false))]]],
            entities: [
                GameEntity(
                    letter: playerConfig.letter.first ?? "P",
                    position: GridCoord(x: 0, y: 0, story: 0),
                    isPlayer: true
                ),
            ],
            spawn: GridCoord(x: 0, y: 0, story: 0),
            healthCount: health,
            energyCount: energy
        )
    }
}
