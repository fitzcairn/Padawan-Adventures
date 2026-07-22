import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct PlayerSelectModelTests {
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

    @Test func reloadPlayersReflectsStore() async throws {
        let session = try makeSession()
        try await session.playerStore.createPlayer(
            name: "Ahsoka",
            initialState: PlayerGameState(health: 3, energy: 2)
        )
        let model = PlayerSelectModel(session: session)

        await model.reloadPlayers()
        #expect(model.playerNames == ["Ahsoka"])
    }

    @Test func selectPlayerBindsAndSucceeds() async throws {
        let session = try makeSession()
        try await session.playerStore.createPlayer(
            name: "Rex",
            initialState: PlayerGameState(health: 3, energy: 2)
        )
        let model = PlayerSelectModel(session: session)

        let ok = await model.selectPlayer(named: "Rex")
        #expect(ok)
        #expect(session.currentPlayerName == "Rex")
    }

    @Test func createPlayerBindsNewPlayer() async throws {
        let session = try makeSession()
        let model = PlayerSelectModel(session: session)
        model.newPlayerName = "  Cody  "

        let ok = await model.createPlayer()
        #expect(ok)
        #expect(session.currentPlayerName == "Cody")
        #expect(try await session.playerStore.listPlayers() == ["Cody"])
    }

    @Test func createPlayerSurfacesDuplicateName() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Echo")
        let model = PlayerSelectModel(session: session)
        model.newPlayerName = "Echo"

        let ok = await model.createPlayer()
        #expect(!ok)
        #expect(model.isShowingDuplicateNameAlert)
        #expect(model.attemptedDuplicateName == "Echo")
    }

    @Test func deletePendingPlayerRemovesFromRoster() async throws {
        let session = try makeSession()
        try await session.playerStore.createPlayer(
            name: "Fives",
            initialState: PlayerGameState(health: 3, energy: 2)
        )
        let model = PlayerSelectModel(session: session)
        await model.reloadPlayers()
        model.confirmDelete(playerName: "Fives")
        #expect(model.isShowingDeleteConfirm)

        await model.deletePendingPlayer()
        #expect(model.playerNames.isEmpty)
        #expect(try await session.playerStore.listPlayers().isEmpty)
    }
}
