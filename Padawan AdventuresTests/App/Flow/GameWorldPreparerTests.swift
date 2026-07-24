import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct GameWorldPreparerTests {
    private func makeSession() throws -> AppSession {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PlayerStateStore(directoryURL: directory)
        let saveService = try GameSaveService(directoryURL: directory)
        return AppSession(
            seedConfig: AppSession.fallbackConfig(),
            playerStore: store,
            saveService: saveService
        )
    }

    @Test func newGameDeletesSaveAndGeneratesWorld() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Rex")
        let existing = TestWorldFactory.emptyFloor(
            width: session.seedConfig.world.width,
            height: session.seedConfig.world.height,
            stories: session.seedConfig.world.stories
        )
        try await session.saveService.save(existing)

        let world = await GameWorldPreparer.loadWorld(session: session, mode: .newGame)
        #expect(world.width >= 1)
        #expect(world.height >= 1)
        #expect(try await session.saveService.load() == nil)
    }

    @Test func newGameRestoresStartingVitalsFromPlayerConfig() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Rex")
        var depleted = TestWorldFactory.emptyFloor(
            width: session.seedConfig.world.width,
            height: session.seedConfig.world.height,
            stories: session.seedConfig.world.stories
        )
        depleted.healthCount = 1
        depleted.energyCount = 0
        await session.syncVitals(from: depleted)
        #expect(session.playerState?.health == 1)
        #expect(session.playerState?.energy == 0)

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
            width: session.seedConfig.world.width,
            height: session.seedConfig.world.height,
            stories: session.seedConfig.world.stories
        )
        saved.healthCount = 7
        try await session.saveService.save(saved)

        let world = await GameWorldPreparer.loadWorld(session: session, mode: .continueSave)
        #expect(world.healthCount == 7)
    }

    @Test func newGameResetsLevelStarsCurrent() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Cody")
        try session.selectLevel(resourceName: "1-tython")
        await session.addLevelStar(resourceName: "1-tython")
        await session.addLevelStar(resourceName: "1-tython")
        #expect(session.playerState?.levels["1-tython"]?.starsCurrent == 2)

        _ = await GameWorldPreparer.prepareLaunch(session: session, mode: .newGame)
        #expect(session.playerState?.levels["1-tython"]?.starsCurrent == 0)
        #expect(session.playerState?.levels["1-tython"]?.started == true)
    }
}
