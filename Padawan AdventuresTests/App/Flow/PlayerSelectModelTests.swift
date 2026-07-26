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
            appConfig: AppSession.fallbackAppConfig(),
            selectedLevel: .fallback,
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
        let model = PlayerSelectModel(
            session: session,
            frontCamera: FixedFrontCameraAvailability(isFrontCameraAvailable: false)
        )

        await model.reloadPlayers()
        #expect(model.playerNames == ["Ahsoka"])
    }

    @Test func selectPlayerBindsAndSucceeds() async throws {
        let session = try makeSession()
        try await session.playerStore.createPlayer(
            name: "Rex",
            initialState: PlayerGameState(health: 3, energy: 2)
        )
        let model = PlayerSelectModel(
            session: session,
            frontCamera: FixedFrontCameraAvailability(isFrontCameraAvailable: false)
        )

        let ok = await model.selectPlayer(named: "Rex")
        #expect(ok)
        #expect(session.currentPlayerName == "Rex")
    }

    @Test func createPlayerWithoutFrontCameraSavesAvatarAndShowsMenu() async throws {
        let session = try makeSession()
        let model = PlayerSelectModel(
            session: session,
            frontCamera: FixedFrontCameraAvailability(isFrontCameraAvailable: false)
        )
        model.newPlayerName = "  Cody  "

        let outcome = await model.createPlayer()
        #expect(outcome == .showMenu)
        #expect(session.currentPlayerName == "Cody")
        #expect(try await session.playerStore.listPlayers() == ["Cody"])
        let avatar = await session.playerStore.loadAvatar(for: "Cody")
        #expect(avatar != nil)
        #expect(avatar?.isEmpty == false)
    }

    @Test func createPlayerWithFrontCameraShowsSelfie() async throws {
        let session = try makeSession()
        let model = PlayerSelectModel(
            session: session,
            frontCamera: FixedFrontCameraAvailability(isFrontCameraAvailable: true)
        )
        model.newPlayerName = "Wolffe"

        let outcome = await model.createPlayer()
        #expect(outcome == .showSelfie)
        #expect(session.currentPlayerName == "Wolffe")
        let avatar = await session.playerStore.loadAvatar(for: "Wolffe")
        #expect(avatar == nil)
    }

    @Test func createPlayerSurfacesDuplicateName() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Echo")
        let model = PlayerSelectModel(
            session: session,
            frontCamera: FixedFrontCameraAvailability(isFrontCameraAvailable: false)
        )
        model.newPlayerName = "Echo"

        let outcome = await model.createPlayer()
        #expect(outcome == .failed)
        #expect(model.isShowingDuplicateNameAlert)
        #expect(model.attemptedDuplicateName == "Echo")
    }

    @Test func deletePendingPlayerRemovesFromRoster() async throws {
        let session = try makeSession()
        try await session.playerStore.createPlayer(
            name: "Fives",
            initialState: PlayerGameState(health: 3, energy: 2)
        )
        let model = PlayerSelectModel(
            session: session,
            frontCamera: FixedFrontCameraAvailability(isFrontCameraAvailable: false)
        )
        await model.reloadPlayers()
        model.confirmDelete(playerName: "Fives")
        #expect(model.isShowingDeleteConfirm)

        await model.deletePendingPlayer()
        #expect(model.playerNames.isEmpty)
        #expect(try await session.playerStore.listPlayers().isEmpty)
    }

    @Test func reloadPlayersLoadsAvatars() async throws {
        let session = try makeSession()
        try await session.playerStore.createPlayer(
            name: "Bly",
            initialState: PlayerGameState(health: 3, energy: 2)
        )
        let jpeg = SillyFaceAvatarGenerator.proceduralJPEG(seedName: "Bly")
        try await session.playerStore.saveAvatar(jpeg, for: "Bly")

        let model = PlayerSelectModel(
            session: session,
            frontCamera: FixedFrontCameraAvailability(isFrontCameraAvailable: false)
        )
        await model.reloadPlayers()
        #expect(model.avatarDataByName["Bly"] != nil)
    }
}
