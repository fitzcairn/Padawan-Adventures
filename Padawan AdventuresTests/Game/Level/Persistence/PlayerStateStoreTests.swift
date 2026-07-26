import Foundation
import Testing
@testable import Padawan_Adventures

struct PlayerStateStoreTests {
    private func makeStore() throws -> (PlayerStateStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PlayerStateStore(directoryURL: directory)
        return (store, directory)
    }

    private func initialState(health: Int = 3, energy: Int = 2) -> PlayerGameState {
        PlayerGameState(health: health, energy: energy)
    }

    @Test func createListsAndLoadsPlayer() async throws {
        let (store, _) = try makeStore()
        try await store.createPlayer(name: "  Ahsoka  ", initialState: initialState())

        let roster = try await store.listPlayers()
        #expect(roster == ["Ahsoka"])

        let state = try await store.loadState(for: "Ahsoka")
        #expect(state.health == 3)
        #expect(state.energy == 2)
        #expect(state.stats.enemiesKilled == 0)
        #expect(state.levels.isEmpty)
    }

    @Test func createRejectsDuplicateNames() async throws {
        let (store, _) = try makeStore()
        try await store.createPlayer(name: "Rex", initialState: initialState())

        await #expect(throws: PlayerStateError.nameNotUnique) {
            try await store.createPlayer(name: "Rex", initialState: initialState(health: 9))
        }

        let roster = try await store.listPlayers()
        #expect(roster == ["Rex"])
    }

    @Test func createRejectsEmptyName() async throws {
        let (store, _) = try makeStore()
        await #expect(throws: PlayerStateError.emptyName) {
            try await store.createPlayer(name: "   ", initialState: initialState())
        }
    }

    @Test func deleteRemovesRosterEntryAndFiles() async throws {
        let (store, root) = try makeStore()
        try await store.createPlayer(name: "Cody", initialState: initialState())

        let saveService = try await store.makeSaveService(for: "Cody")
        try await saveService.save(TestWorldFactory.emptyFloor(width: 3, height: 3))

        let playerDir = await store.playerDirectoryURL(for: "Cody")
        #expect(FileManager.default.fileExists(atPath: playerDir.path))

        try await store.deletePlayer(name: "Cody")
        #expect(try await store.listPlayers().isEmpty)
        #expect(FileManager.default.fileExists(atPath: playerDir.path) == false)

        let rosterURL = root.appendingPathComponent(PlayerStateStore.rosterFileName)
        let data = try Data(contentsOf: rosterURL)
        let roster = try JSONDecoder().decode([String].self, from: data)
        #expect(roster.isEmpty)
    }

    @Test func purgeOrphansRemovesUnlistedPlayerDirsAndLegacySave() async throws {
        let (store, root) = try makeStore()
        try await store.createPlayer(name: "Echo", initialState: initialState())

        let orphanDir = root
            .appendingPathComponent(PlayerStateStore.playersDirectoryName, isDirectory: true)
            .appendingPathComponent(PlayerStateStore.encodedDirectoryName(for: "Orphan"), isDirectory: true)
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try Data("orphan".utf8).write(to: orphanDir.appendingPathComponent("state.plist"))

        let legacySave = root.appendingPathComponent(GameSaveService.saveFileName)
        try Data("legacy".utf8).write(to: legacySave)

        try await store.purgeOrphans()

        #expect(FileManager.default.fileExists(atPath: orphanDir.path) == false)
        #expect(FileManager.default.fileExists(atPath: legacySave.path) == false)

        let echoDir = await store.playerDirectoryURL(for: "Echo")
        #expect(FileManager.default.fileExists(atPath: echoDir.path))
        #expect(try await store.listPlayers() == ["Echo"])
    }

    @Test func playerGameStateRoundTripPreservesProgressAndStats() async throws {
        let (store, _) = try makeStore()
        var state = initialState(health: 5, energy: 4)
        state.markLevelStarted("level_2")
        state.markLevelCompleted("level_1", artifact: "key.fill")
        state.levels["level_1"]?.starsEarned = 2
        state.levels["level_2"]?.starsCurrent = 4
        state.totalStars = 2
        state.stats.gatesOpened = 3
        state.stats.pitsCrossed = 4
        state.stats.enemiesKilled = 7
        state.stats.extras["secretsFound"] = 2

        try await store.createPlayer(name: "Fives", initialState: state)
        let restored = try await store.loadState(for: "Fives")

        #expect(restored.lastLevelStarted == "level_2")
        #expect(restored.levels["level_1"]?.completed == true)
        #expect(restored.levels["level_1"]?.starsEarned == 2)
        #expect(restored.levels["level_2"]?.started == true)
        #expect(restored.levels["level_2"]?.starsCurrent == 4)
        #expect(restored.totalStars == 2)
        #expect(restored.stats.gatesOpened == 3)
        #expect(restored.stats.enemiesKilled == 7)
        #expect(restored.stats.extras["secretsFound"] == 2)
        #expect(restored.inventory.artifacts == ["key.fill"])
        #expect(restored.health == 5)
        #expect(restored.energy == 4)
    }

    @Test func playerGameStateDecodesMissingFieldsWithDefaults() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let minimal = ["version": 1, "health": 2, "energy": 1] as [String: Any]
        let data = try PropertyListSerialization.data(fromPropertyList: minimal, format: .binary, options: 0)
        let decoded = try PropertyListDecoder().decode(PlayerGameState.self, from: data)

        #expect(decoded.health == 2)
        #expect(decoded.energy == 1)
        #expect(decoded.levels.isEmpty)
        #expect(decoded.totalStars == 0)
        #expect(decoded.stats.gatesOpened == 0)
        #expect(decoded.stats.extras.isEmpty)
        #expect(decoded.inventory == PlayerInventory())
        #expect(decoded.settings == .default)
    }

    @Test func playerGameStatePersistsSettings() async throws {
        let (store, _) = try makeStore()
        let settings = PlayerSettings(
            soundEffectsEnabled: false,
            soundEffectsVolume: 0.25,
            musicEnabled: false,
            musicVolume: 0.5
        )
        try await store.createPlayer(
            name: "Rex",
            initialState: PlayerGameState(health: 3, energy: 2, settings: settings)
        )

        let restored = try await store.loadState(for: "Rex")
        #expect(restored.settings == settings)
    }

    @Test func makeSaveServiceIsPerPlayer() async throws {
        let (store, _) = try makeStore()
        try await store.createPlayer(name: "Wolffe", initialState: initialState())
        try await store.createPlayer(name: "Bly", initialState: initialState())

        let wolffeSave = try await store.makeSaveService(for: "Wolffe")
        let blySave = try await store.makeSaveService(for: "Bly")

        var wolffeWorld = TestWorldFactory.emptyFloor(width: 4, height: 4)
        wolffeWorld.setPlayerPosition(GridCoord(x: 1, y: 1, story: 0))
        try await wolffeSave.save(wolffeWorld)

        #expect(try await blySave.load() == nil)
        let restored = try await wolffeSave.load()
        #expect(restored?.playerPosition == GridCoord(x: 1, y: 1, story: 0))
    }

    @Test func encodedDirectoryNamesRoundTripSpecialCharacters() {
        let name = "Padawan Obi-Wan / Anakin"
        let encoded = PlayerStateStore.encodedDirectoryName(for: name)
        #expect(encoded.contains("/") == false)
        #expect(PlayerStateStore.decodedPlayerName(fromDirectoryName: encoded) == name)
    }

    @Test func avatarSaveLoadAndDeleteWithPlayer() async throws {
        let (store, _) = try makeStore()
        try await store.createPlayer(name: "Gree", initialState: initialState())

        let jpeg = SillyFaceAvatarGenerator.proceduralJPEG(seedName: "Gree")
        #expect(!jpeg.isEmpty)
        try await store.saveAvatar(jpeg, for: "Gree")

        let loaded = await store.loadAvatar(for: "Gree")
        #expect(loaded == jpeg)

        let avatarURL = await store.avatarURL(for: "Gree")
        #expect(FileManager.default.fileExists(atPath: avatarURL.path))

        try await store.deletePlayer(name: "Gree")
        #expect(FileManager.default.fileExists(atPath: avatarURL.path) == false)
        #expect(await store.loadAvatar(for: "Gree") == nil)
    }
}
