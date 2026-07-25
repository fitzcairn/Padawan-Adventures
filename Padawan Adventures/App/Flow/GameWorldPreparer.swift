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

        return await loadWorld(session: session, mode: mode)
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

    @MainActor
    private static func generateWorld(session: AppSession) async -> GameWorld {
        let config = session.seedConfig
        let playerConfig = session.playerConfig
        let enemyConfig = session.enemyConfig
        let health = session.playerState?.health ?? playerConfig.startingHealth
        let energy = session.playerState?.energy ?? playerConfig.startingEnergy

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
