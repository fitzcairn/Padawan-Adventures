import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct AppSessionTests {
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

    @Test func fallbackConfigIsSingleStory() {
        let config = AppSession.fallbackConfig()
        #expect(config.world.stories == 1)
        #expect(config.enemies?.type == "grunt")
        #expect(config.enemies?.spawnChancePerRoom == 0.8)
    }

    @Test func continueIneligibleWhenSaveMissing() {
        let config = AppSession.fallbackConfig()
        #expect(AppSession.isContinueEligible(savedWorld: nil, config: config) == false)
    }

    @Test func continueEligibleWhenDimensionsMatch() {
        let config = AppSession.fallbackConfig()
        let world = TestWorldFactory.emptyFloor(
            width: config.world.width,
            height: config.world.height,
            stories: config.world.stories
        )
        #expect(AppSession.isContinueEligible(savedWorld: world, config: config))
    }

    @Test func continueIneligibleWhenDimensionsDiffer() {
        let config = AppSession.fallbackConfig()
        let world = TestWorldFactory.emptyFloor(width: 4, height: 4, stories: 1)
        #expect(AppSession.isContinueEligible(savedWorld: world, config: config) == false)
    }

    @Test func deleteRemovesSaveFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = try GameSaveService(directoryURL: directory)

        let world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        try await service.save(world)
        #expect(try await service.load() != nil)

        try await service.delete()
        #expect(try await service.load() == nil)
    }

    @Test func createAndBindPlayerSetsCurrentPlayer() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "  Ahsoka  ")
        #expect(session.currentPlayerName == "Ahsoka")
        #expect(session.playerState?.health == session.playerConfig.startingHealth)
        #expect(session.hasCompatibleSave == false)
    }

    @Test func bindPlayerLoadsExistingState() async throws {
        let session = try makeSession()
        try await session.playerStore.createPlayer(
            name: "Rex",
            initialState: PlayerGameState(health: 5, energy: 4)
        )
        try await session.bindPlayer(name: "Rex")
        #expect(session.currentPlayerName == "Rex")
        #expect(session.playerState?.health == 5)
        #expect(session.playerState?.energy == 4)
    }

    @Test func deletePlayerClearsBoundPlayer() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Cody")
        try await session.deletePlayer(name: "Cody")
        #expect(session.currentPlayerName == nil)
        #expect(session.playerState == nil)
        #expect(session.hasCompatibleSave == false)
    }

    @Test func refreshContinueEligibilityRequiresCompatibleSave() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Echo")
        await session.refreshContinueEligibility()
        #expect(session.hasCompatibleSave == false)

        let world = TestWorldFactory.emptyFloor(
            width: session.seedConfig.world.width,
            height: session.seedConfig.world.height,
            stories: session.seedConfig.world.stories
        )
        try await session.saveService.save(world)
        await session.refreshContinueEligibility()
        #expect(session.hasCompatibleSave)
    }
}
