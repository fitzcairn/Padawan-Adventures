import Foundation
import SpriteKit

enum GameWorldPreparer {
    /// Sprite warming occupies the first slice; world gen fills the rest.
    private static let assetsEnd = 0.48

    /// Warms level sprites and builds the world. Returns `nil` when enemy sprites
    /// could not be fully loaded — callers must not present gameplay in that case.
    @MainActor
    static func prepareLaunch(
        session: AppSession,
        mode: GameLaunchMode,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> GameWorld? {
        func report(_ value: Double) {
            onProgress?(min(1, max(0, value)))
        }

        GameLogger.mark(
            .world,
            "prepareLaunch mode=\(mode) level='\(session.selectedLevelName)'"
        )

        if mode == .continueSave, let lastLevel = session.playerState?.lastLevelStarted {
            do {
                try session.selectLevel(resourceName: lastLevel)
            } catch {
                GameLogger.error(.world, "continue: could not select '\(lastLevel)': \(error)")
            }
        }
        session.resetVocabularySampler()

        if let resourceName = session.selectedLevelResourceName {
            if mode == .newGame {
                await session.resetLevelStarsCurrent(resourceName: resourceName)
                if session.appConfig.demoMode {
                    await session.addLevelStars(resourceName: resourceName, count: 1000)
                }
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
        await session.ensureItemSpritesLoaded(includeAllTreasures: false) { local in
            report(LoadProgress.map(local, from: 0.18, to: 0.26))
        }
        let enemiesReady = await session.ensureEnemySpritesLoaded { local in
            report(LoadProgress.map(local, from: 0.26, to: 0.38))
        }
        guard enemiesReady else {
            GameLogger.fault(.world, "aborting launch — enemy sprites incomplete")
            session.releaseLevelScopedAssets()
            session.startObservingMemoryPressure()
            return nil
        }
        await session.ensureNpcSpritesLoaded { local in
            report(LoadProgress.map(local, from: 0.38, to: 0.40))
        }

        // Warm per-level tile sets before GPU upload so the world does not decode mid-frame.
        await session.ensureFloorTileSetLoaded { local in
            report(LoadProgress.map(local, from: 0.40, to: 0.44))
        }
        await session.ensureLetterSpriteSetLoaded { local in
            report(LoadProgress.map(local, from: 0.44, to: 0.46))
        }
        await session.ensurePitSpriteSetLoaded { local in
            report(LoadProgress.map(local, from: 0.46, to: 0.48))
        }
        await session.ensureGateSpriteSetLoaded { local in
            report(LoadProgress.map(local, from: 0.48, to: assetsEnd))
        }

        GameLogger.mark(.world, "level assets warmed; uploading textures")
        let textures =
            session.spriteLibrary.allTextures()
            + session.floorTileSetLibrary.allTextures()
            + session.letterSpriteSetLibrary.allTextures()
            + session.pitSpriteSetLibrary.allTextures()
            + session.gateSpriteSetLibrary.allTextures()
            + session.ensureGateMinigameArtLoaded()
        await withCheckedContinuation { continuation in
            SKTexture.preload(textures) {
                continuation.resume()
            }
        }
        report(assetsEnd)

        let world = await GameLogger.step(.world, "loadWorld(\(mode))") {
            await loadWorld(session: session, mode: mode) { local in
                report(LoadProgress.map(local, from: assetsEnd, to: 1))
            }
        }
        MemoryProbe.mark("world-ready sprites=\(session.spriteLibrary.residentBytes / 1_048_576)MB")
        return world
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
            if var saved = try? await session.saveService.load(),
               WorldLoader.isCompatibleSave(saved, with: session.generationConfig) {
                await attachFloorSet(to: &saved, session: session)
                saved.retileAllFloorsIfNeeded()
                report(1)
                return saved
            }
            return await generateWorld(session: session, onProgress: onProgress)

        case .newGame:
            try? await session.saveService.delete()
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

        await session.ensureFloorTileSetLoaded()
        await session.ensureLetterSpriteSetLoaded()
        await session.ensurePitSpriteSetLoaded()
        await session.ensureGateSpriteSetLoaded()
        let floorTileSet: FloorTileSet
        if let loaded = session.floorTileSetLibrary.tileSet {
            floorTileSet = loaded
        } else {
            do {
                floorTileSet = try FloorTileSet.loadFromBundle(set: config.floorSet)
            } catch {
                onProgress?(1)
                return minimalWorld(health: health, energy: energy, playerConfig: playerConfig)
            }
        }

        if session.appConfig.demoMode {
            var world = DemoWorldBuilder.build(
                level: session.selectedLevel,
                playerConfig: playerConfig,
                enemyConfig: enemyConfig,
                floorTileSet: floorTileSet
            )
            world.healthCount = health
            world.energyCount = energy
            onProgress?(1)
            return world
        }

        do {
            var world = try await Task.detached(priority: .userInitiated) {
                try ProceduralGenerator().generate(
                    from: config,
                    playerConfig: playerConfig,
                    enemyConfig: enemyConfig,
                    floorTileSet: floorTileSet,
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
                let fallbackSet = (try? FloorTileSet.loadFromBundle(set: fallback.floorSet))
                    ?? floorTileSet
                var world = try await Task.detached(priority: .userInitiated) {
                    try ProceduralGenerator().generate(
                        from: fallback,
                        playerConfig: .fallback,
                        enemyConfig: .fallback,
                        floorTileSet: fallbackSet,
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

    @MainActor
    private static func attachFloorSet(to world: inout GameWorld, session: AppSession) async {
        await session.ensureFloorTileSetLoaded()
        await session.ensureLetterSpriteSetLoaded()
        await session.ensurePitSpriteSetLoaded()
        await session.ensureGateSpriteSetLoaded()
        if let set = session.floorTileSetLibrary.tileSet {
            world.floorSet = set
            world.floorSetName = set.meta.floorSet
        } else {
            let name = world.floorSetName ?? session.generationConfig.floorSet
            if let set = try? FloorTileSet.loadFromBundle(set: name) {
                world.floorSet = set
                world.floorSetName = name
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
