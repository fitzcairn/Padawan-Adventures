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
            selectedLevelResourceName: "1-tython",
            selectedLevelArtifact: "key.fill",
            playerStore: store,
            saveService: saveService
        )
    }

    @Test func completingLevelMarksProgressAndClearsMidRunSave() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Win")
        await session.markLevelStarted(resourceName: "1-tython")

        let world = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        try await session.saveService.save(world)
        await session.refreshContinueEligibility()
        #expect(session.hasCompatibleSave)

        await GameRunExitHandler.persistExitState(
            completedLevel: true,
            world: world,
            session: session
        )

        #expect(session.playerState?.levels["1-tython"]?.completed == true)
        #expect(try await session.saveService.load() == nil)
        #expect(session.hasCompatibleSave == false)
        // Campaign progress must keep CONTINUE available after the mid-run save is deleted.
        #expect(session.shouldShowContinue)
        #expect(session.continueDestination == .levelSelect)

        let reloaded = try await session.playerStore.loadState(for: "Win")
        #expect(reloaded.levels["1-tython"]?.completed == true)
        #expect(reloaded.lastLevelStarted == "1-tython")
    }

    @Test func completingLevelPersistsEvenWithoutWorldSnapshot() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "NoWorld")
        await session.markLevelStarted(resourceName: "1-tython")

        let world = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        try await session.saveService.save(world)

        await GameRunExitHandler.persistExitState(
            completedLevel: true,
            world: nil,
            session: session
        )

        #expect(session.playerState?.levels["1-tython"]?.completed == true)
        #expect(try await session.saveService.load() == nil)
        #expect(session.shouldShowContinue)
        #expect(session.continueDestination == .levelSelect)
    }

    @Test func fleeingPersistsMidRunSaveForContinue() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Flee")
        await session.markLevelStarted(resourceName: "1-tython")

        var world = TestWorldFactory.emptyFloor(
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        world.healthCount = 3
        world.energyCount = 2

        await GameRunExitHandler.persistExitState(
            completedLevel: false,
            world: world,
            session: session
        )

        #expect(session.playerState?.levels["1-tython"]?.completed != true)
        #expect(try await session.saveService.load() != nil)
        #expect(session.hasCompatibleSave)
        #expect(session.shouldShowContinue)
        #expect(session.continueDestination == .resumeSave)
        #expect(session.playerState?.health == 3)
        #expect(session.playerState?.energy == 2)
    }
}
