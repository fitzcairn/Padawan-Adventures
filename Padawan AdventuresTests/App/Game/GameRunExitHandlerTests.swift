import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct GameRunExitHandlerTests {
    private func makeSession() throws -> AppSession {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PlayerStateStore(directoryURL: directory)
        let saveService = try GameSaveService(directoryURL: directory)
        return AppSession(
            appConfig: AppSession.fallbackAppConfig(),
            selectedLevel: .fallback,
            playerStore: store,
            saveService: saveService
        )
    }

    private func bindAndSelectLevel(_ session: AppSession, player: String) async throws -> String {
        try await session.createAndBindPlayer(name: player)
        let resourceName = try #require(LevelCatalog.loadFromBundle().first?.resourceName)
        try session.selectLevel(resourceName: resourceName)
        await session.markLevelStarted(resourceName: resourceName)
        return resourceName
    }

    private func compatibleWorld(for session: AppSession) -> GameWorld {
        TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
    }

    @Test func completingLevelMarksProgressAndClearsMidRunSave() async throws {
        let session = try makeSession()
        let resourceName = try await bindAndSelectLevel(session, player: "Win")

        let world = compatibleWorld(for: session)
        try await session.saveService.save(world)
        await session.refreshContinueEligibility()
        #expect(session.hasCompatibleSave)

        await GameRunExitHandler.persistExitState(
            completedLevel: true,
            world: world,
            session: session
        )

        #expect(session.playerState?.levels[resourceName]?.completed == true)
        #expect(try await session.saveService.load() == nil)
        #expect(session.hasCompatibleSave == false)
        // Campaign progress must keep CONTINUE available after the mid-run save is deleted.
        #expect(session.shouldShowContinue)
        #expect(session.continueDestination == .levelSelect)

        let reloaded = try await session.playerStore.loadState(for: "Win")
        #expect(reloaded.levels[resourceName]?.completed == true)
        #expect(reloaded.lastLevelStarted == resourceName)
    }

    @Test func completingLevelPersistsEvenWithoutWorldSnapshot() async throws {
        let session = try makeSession()
        let resourceName = try await bindAndSelectLevel(session, player: "NoWorld")

        try await session.saveService.save(compatibleWorld(for: session))

        await GameRunExitHandler.persistExitState(
            completedLevel: true,
            world: nil,
            session: session
        )

        #expect(session.playerState?.levels[resourceName]?.completed == true)
        #expect(try await session.saveService.load() == nil)
        #expect(session.shouldShowContinue)
        #expect(session.continueDestination == .levelSelect)
    }

    @Test func fleeingPersistsMidRunSaveForContinue() async throws {
        let session = try makeSession()
        let resourceName = try await bindAndSelectLevel(session, player: "Flee")

        var world = compatibleWorld(for: session)
        world.healthCount = 3
        world.energyCount = 2

        await GameRunExitHandler.persistExitState(
            completedLevel: false,
            world: world,
            session: session
        )

        #expect(session.playerState?.levels[resourceName]?.completed != true)
        #expect(try await session.saveService.load() != nil)
        #expect(session.hasCompatibleSave)
        #expect(session.shouldShowContinue)
        #expect(session.continueDestination == .resumeSave)
        #expect(session.playerState?.health == 3)
        #expect(session.playerState?.energy == 2)
    }
}
