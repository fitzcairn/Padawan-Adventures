import Foundation
import SpriteKit

enum GameWorldPreparer {
    /// Sprite warming occupies the first slice; world gen fills the rest.
    private static let assetsEnd = 0.48

    @MainActor
    static func prepareLaunch(
        session: AppSession,
        mode: GameLaunchMode,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> GameWorld {
        func report(_ value: Double) {
            onProgress?(min(1, max(0, value)))
        }

        if mode == .continueSave, let lastLevel = session.playerState?.lastLevelStarted {
            try? session.selectLevel(resourceName: lastLevel)
        }

        if let resourceName = session.selectedLevelResourceName {
            if mode == .newGame {
                await session.resetLevelStarsCurrent(resourceName: resourceName)
            }
            await session.markLevelStarted(resourceName: resourceName)
        }
        report(0.02)

        // Drop level-scoped textures under memory pressure only while on menus;
        // stop before loading enemies so a warning mid-level cannot blank them.
        session.stopObservingMemoryPressure()

        // Warm sprite cache once per session before the world is presented.
        await session.ensurePlayerSpritesLoaded { local in
            report(LoadProgress.map(local, from: 0.02, to: 0.18))
        }
        await session.ensureItemSpritesLoaded { local in
            report(LoadProgress.map(local, from: 0.18, to: 0.26))
        }
        await session.ensureEnemySpritesLoaded { local in
            report(LoadProgress.map(local, from: 0.26, to: assetsEnd))
        }

        await withCheckedContinuation { continuation in
            SKTexture.preload(session.spriteLibrary.allTextures()) {
                continuation.resume()
            }
        }
        report(assetsEnd)

        return await loadWorld(session: session, mode: mode) { local in
            report(LoadProgress.map(local, from: assetsEnd, to: 1))
        }
    }

    @MainActor
    static func loadWorld(
        session: AppSession,
        mode: GameLaunchMode,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> GameWorld {
        func report(_ value: Double) {
            onProgress?(min(1, max(0, value)))
        }

        switch mode {
        case .continueSave:
            report(0.05)
            if let saved = try? await session.saveService.load(),
               WorldLoader.isCompatibleSave(saved, with: session.generationConfig) {
                report(1)
                return saved
            }
            return await generateWorld(session: session, onProgress: onProgress)

        case .newGame:
            try? await session.saveService.delete()
            await session.resetVitalsToStarting()
            report(0.05)
            return await generateWorld(session: session, onProgress: onProgress)
        }
    }

    @MainActor
    private static func generateWorld(
        session: AppSession,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> GameWorld {
        let config = session.generationConfig
        let playerConfig = session.playerConfig
        let enemyConfig = session.enemyConfig
        let health = session.playerState?.health ?? playerConfig.startingHealth
        let energy = session.playerState?.energy ?? playerConfig.startingEnergy

        let terrainPlacement = session.terrainCatalog.placementTable
        do {
            var world = try await Task.detached(priority: .userInitiated) {
                try ProceduralGenerator().generate(
                    from: config,
                    playerConfig: playerConfig,
                    enemyConfig: enemyConfig,
                    terrainPlacement: terrainPlacement,
                    onProgress: { fraction in
                        Task { @MainActor in
                            onProgress?(fraction)
                        }
                    }
                )
            }.value
            world.healthCount = health
            world.energyCount = energy
            onProgress?(1)
            return world
        } catch {
            let fallback = WorldGenerationConfig.compose(
                app: AppSession.fallbackAppConfig(),
                level: .fallback
            )
            do {
                var world = try await Task.detached(priority: .userInitiated) {
                    try ProceduralGenerator().generate(
                        from: fallback,
                        playerConfig: .fallback,
                        enemyConfig: .fallback,
                        terrainPlacement: terrainPlacement,
                        onProgress: { fraction in
                            Task { @MainActor in
                                onProgress?(fraction)
                            }
                        }
                    )
                }.value
                world.healthCount = health
                world.energyCount = energy
                onProgress?(1)
                return world
            } catch {
                onProgress?(1)
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
