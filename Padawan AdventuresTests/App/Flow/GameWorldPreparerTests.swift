import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct GameWorldPreparerTests {
    @Test func newGameDeletesSaveAndGeneratesWorld() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Rex")
        let existing = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        try await session.saveService.save(existing)

        let world = await GameWorldPreparer.loadWorld(session: session, mode: .newGame)
        #expect(world.width >= 1)
        #expect(world.height >= 1)
        #expect(try await session.saveService.load() == nil)
    }

    @Test func newGameKeepsSessionVitals() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Rex")
        var depleted = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        depleted.healthCount = 5
        depleted.energyCount = 0
        await session.syncVitals(from: depleted)
        #expect(session.playerState?.health == 5)
        #expect(session.playerState?.energy == 0)

        let world = await GameWorldPreparer.loadWorld(session: session, mode: .newGame)

        #expect(world.healthCount == 5)
        #expect(world.energyCount == 0)
        #expect(session.playerState?.health == 5)
        #expect(session.playerState?.energy == 0)
    }

    @Test func beginNewGameThenNewGameRestoresStartingVitals() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Rex")
        var depleted = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        depleted.healthCount = 5
        depleted.energyCount = 0
        await session.syncVitals(from: depleted)

        await session.beginNewGame()
        let world = await GameWorldPreparer.loadWorld(session: session, mode: .newGame)

        #expect(world.healthCount == session.playerConfig.startingHealth)
        #expect(world.energyCount == session.playerConfig.startingEnergy)
        #expect(session.playerState?.health == session.playerConfig.startingHealth)
        #expect(session.playerState?.energy == session.playerConfig.startingEnergy)
    }

    @Test func continueSaveUsesCompatibleSave() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Ahsoka")
        var saved = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        saved.healthCount = 7
        try await session.saveService.save(saved)

        let world = await GameWorldPreparer.loadWorld(session: session, mode: .continueSave)
        #expect(world.healthCount == 7)
    }

    @Test func newGameKeepsPlaythroughCoins() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Cody")
        try session.selectLevel(resourceName: "1-tython")
        session.appConfig.demoMode = false
        await session.addLevelStar(resourceName: "1-tython")
        await session.addLevelStar(resourceName: "1-tython")
        #expect(session.playerState?.totalStars == 2)

        let world = await GameWorldPreparer.prepareLaunch(session: session, mode: .newGame)
        #expect(world != nil)
        #expect(session.playerState?.totalStars == 2)
        #expect(session.playerState?.levels["1-tython"]?.started == true)
    }

    @Test func demoNewGameSeedsThousandCoins() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Demo")
        try session.selectLevel(resourceName: "1-tython")
        session.appConfig.demoMode = true
        _ = await GameWorldPreparer.prepareLaunch(session: session, mode: .newGame)
        #expect(session.playerState?.totalStars == 1000)
    }

    @Test func nonDemoNewGameKeepsEarnedCoins() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Cody")
        try session.selectLevel(resourceName: "1-tython")
        session.appConfig.demoMode = false
        await session.addLevelStars(resourceName: "1-tython", count: 2)
        _ = await GameWorldPreparer.prepareLaunch(session: session, mode: .newGame)
        #expect(session.playerState?.totalStars == 2)
    }

    @Test func continueSaveDoesNotReseedDemoCoins() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Demo")
        try session.selectLevel(resourceName: "1-tython")
        session.appConfig.demoMode = true
        await session.addLevelStars(resourceName: "1-tython", count: 5)
        let saved = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        try await session.saveService.save(saved)
        _ = await GameWorldPreparer.prepareLaunch(session: session, mode: .continueSave)
        #expect(session.playerState?.totalStars == 5)
    }

    @Test func ensureEnemySpritesLoadedRejectsIncompleteSprites() async throws {
        let session = try makeSession(enemyConfig: Self.brokenSpiderEnemyConfig())
        let ready = await session.ensureEnemySpritesLoaded()
        #expect(ready == false)
        #expect(session.spriteLibrary.isLoaded(id: "spider") == false)
    }

    @Test func prepareLaunchFailsClosedWhenEnemySpritesMissing() async throws {
        let session = try makeSession(enemyConfig: Self.brokenSpiderEnemyConfig())
        try await session.createAndBindPlayer(name: "Rex")
        let world = await GameWorldPreparer.prepareLaunch(session: session, mode: .newGame)
        #expect(world == nil)
        #expect(session.spriteLibrary.isLoaded(id: "spider") == false)
    }

    @Test func ensureEnemySpritesLoadedWarmsTythonTypes() async throws {
        let enemies = try EnemyConfig.loadFromBundle()
        let session = try makeSession(enemyConfig: enemies)
        try session.selectLevel(resourceName: "1-tython")
        let ready = await session.ensureEnemySpritesLoaded()
        #expect(ready == true)
        #expect(session.spriteLibrary.isLoaded(id: "dino"))
        #expect(session.spriteLibrary.isLoaded(id: "treant"))
        #expect(session.spriteLibrary.animation(id: "dino", named: "idle_down") != nil)
        #expect(session.spriteLibrary.animation(id: "treant", named: "idle_down") != nil)
        #expect(session.spriteLibrary.missingAnimations(
            id: "dino",
            config: try #require(enemies.sprites["dino"])
        ).isEmpty)
    }

    private func makeSession(enemyConfig: EnemyConfig? = nil) throws -> AppSession {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PlayerStateStore(directoryURL: directory)
        let saveService = try GameSaveService(directoryURL: directory)
        return AppSession(
            appConfig: AppSession.fallbackAppConfig(),
            selectedLevel: .fallback,
            enemyConfig: enemyConfig,
            playerStore: store,
            saveService: saveService
        )
    }

    private static func brokenSpiderEnemyConfig() -> EnemyConfig {
        EnemyConfig(
            enemies: [
                "spider": EnemyTypeConfig(
                    letter: "E",
                    color: "#FF0000",
                    tilesPerSecond: 1.0,
                    forgetSeconds: 3.0,
                    sprite: "spider"
                ),
            ],
            sprites: [
                "spider": SpriteConfig(
                    root: "Sprites/Missing",
                    animations: [
                        "idle_down": .sheet(sheet: "missing", atlas: "missing"),
                    ]
                ),
            ]
        )
    }
}
