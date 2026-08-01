import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct AppSessionTests {
    private func makeAudioPreferences() -> AudioPreferences {
        let suiteName = "AppSessionTests.AudioPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AudioPreferences(defaults: defaults)
    }

    private func makeSession(audioPreferences: AudioPreferences? = nil) throws -> AppSession {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try PlayerStateStore(directoryURL: directory)
        let saveService = try GameSaveService(directoryURL: directory)
        return AppSession(
            appConfig: AppSession.fallbackAppConfig(),
            selectedLevel: .fallback,
            playerStore: store,
            saveService: saveService,
            audioPreferences: audioPreferences ?? makeAudioPreferences()
        )
    }

    @Test func fallbackConfigIsSingleStory() {
        let app = AppSession.fallbackAppConfig()
        let level = LevelConfig.fallback
        #expect(app.world.stories == 1)
        #expect(level.enemies?.type == "spider")
        #expect(level.enemies?.spawnChancePerRoom == 0.8)
    }

    @Test func continueIneligibleWhenSaveMissing() {
        let config = WorldGenerationConfig.compose(
            app: AppSession.fallbackAppConfig(),
            level: .fallback
        )
        #expect(AppSession.isContinueEligible(savedWorld: nil, config: config) == false)
    }

    @Test func continueEligibleWhenDimensionsMatch() {
        let config = WorldGenerationConfig.compose(
            app: AppSession.fallbackAppConfig(),
            level: .fallback
        )
        let world = TestWorldFactory.emptyFloor(
            width: config.world.width,
            height: config.world.height,
            stories: config.world.stories
        )
        #expect(AppSession.isContinueEligible(savedWorld: world, config: config))
    }

    @Test func continueIneligibleWhenDimensionsDiffer() {
        let config = WorldGenerationConfig.compose(
            app: AppSession.fallbackAppConfig(),
            level: .fallback
        )
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

    @Test func bindPlayerRestoresSettingsIntoAudioPreferences() async throws {
        let prefs = makeAudioPreferences()
        let session = try makeSession(audioPreferences: prefs)
        let settings = PlayerSettings(
            soundEffectsEnabled: false,
            soundEffectsVolume: 0.3,
            musicEnabled: false,
            musicVolume: 0.6
        )
        let expected = PlayerSettings(
            soundEffectsEnabled: true,
            soundEffectsVolume: 0.3,
            musicEnabled: false,
            musicVolume: 0.6
        )
        try await session.playerStore.createPlayer(
            name: "Rex",
            initialState: PlayerGameState(health: 5, energy: 4, settings: settings)
        )

        prefs.soundEffectsVolume = 1
        prefs.musicEnabled = true
        prefs.musicVolume = 1

        try await session.bindPlayer(name: "Rex")
        #expect(prefs.snapshot == expected)
        #expect(session.playerState?.settings == settings)
    }

    @Test func persistCurrentSettingsWritesBoundPlayerState() async throws {
        let prefs = makeAudioPreferences()
        let session = try makeSession(audioPreferences: prefs)
        try await session.createAndBindPlayer(name: "Fives")

        prefs.soundEffectsVolume = 0.2
        prefs.musicEnabled = false
        prefs.musicVolume = 0.8

        await session.persistCurrentSettings()
        #expect(session.playerState?.settings == prefs.snapshot)
        #expect(prefs.snapshot.soundEffectsEnabled)

        let reloaded = try await session.playerStore.loadState(for: "Fives")
        #expect(reloaded.settings == prefs.snapshot)
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
            width: session.generationConfig.world.width,
            height: session.generationConfig.world.height,
            stories: session.generationConfig.world.stories
        )
        try await session.saveService.save(world)
        await session.refreshContinueEligibility()
        #expect(session.hasCompatibleSave)
    }

    @Test func unlockDadModeRequiresBoundPlayer() async throws {
        let session = try makeSession()
        #expect(session.isDadModeUnlocked == false)
        #expect(await session.unlockDadMode() == false)
        #expect(session.isDadModeUnlocked == false)
    }

    @Test func unlockDadModePersistsAndClearsOnProgressionJump() async throws {
        let session = try makeSession()
        try await session.createAndBindPlayer(name: "Dad")
        #expect(await session.unlockDadMode())
        #expect(session.isDadModeUnlocked)

        let reloaded = try await session.playerStore.loadState(for: "Dad")
        #expect(reloaded.dadModeUnlocked)

        let ordered = LevelCatalog.loadFromBundle().map(\.resourceName)
        guard let target = ordered.dropFirst().first ?? ordered.first else {
            return
        }
        await session.applyDadModeProgression(to: target)
        #expect(session.isDadModeUnlocked == false)
    }

    @Test func loadResourcesWarmsMenuAndLevelSelectAssets() async {
        let session = await AppSession.loadResources()
        #expect(session.spriteLibrary.uiImage(id: "logo") != nil)
        #expect(session.spriteLibrary.uiImages(id: "kam") != nil)
        #expect(session.spriteLibrary.uiImages(id: "yoda") != nil)
        #expect(session.spriteLibrary.uiImages(id: "cutscene_player") != nil)
        #expect(session.spriteLibrary.uiImages(id: "cutscene_yoda") != nil)
        #expect(session.cutsceneVideo.player != nil)
        #expect(session.backgroundLibrary.uiImage(named: "menu_screen_bg") != nil)
        #expect(session.backgroundLibrary.uiImage(named: "level_screen_bg") != nil)
        #expect(ScoreCoinIcon.uiImage() != nil)
        #expect(HudVitalIcon.health.uiImage() != nil)
        #expect(HudVitalIcon.energy.uiImage() != nil)
        #expect(session.spriteLibrary.isLoaded(id: "player"))

        let levels = LevelCatalog.loadFromBundle()
        for level in levels where level.sprite != nil {
            #expect(
                session.spriteLibrary.uiImage(id: level.resourceName, named: "idle") != nil,
                "Missing planet UIImage for \(level.resourceName)"
            )
        }
        if let bootstrapTreasure = session.selectedLevel.treasure {
            #expect(
                session.spriteLibrary.uiImage(id: bootstrapTreasure) != nil,
                "Missing treasure icon for \(bootstrapTreasure)"
            )
            #expect(
                session.spriteLibrary.isLoaded(id: bootstrapTreasure),
                "Missing treasure animation for \(bootstrapTreasure)"
            )
        }
        for treasureID in levels.compactMap(\.treasure) where treasureID != session.selectedLevel.treasure {
            #expect(
                session.spriteLibrary.isLoaded(id: treasureID) == false,
                "Unexpected bootstrap load for unselected treasure \(treasureID)"
            )
        }
    }

    @Test func releaseCutsceneSpritesDropsCutsceneClips() async {
        let session = await AppSession.loadResources()
        #expect(session.spriteLibrary.isLoaded(id: CutsceneSpritesConfig.playerID))
        #expect(session.spriteLibrary.isLoaded(id: CutsceneSpritesConfig.yodaID))
        session.releaseCutsceneSprites()
        #expect(session.spriteLibrary.isLoaded(id: CutsceneSpritesConfig.playerID) == false)
        #expect(session.spriteLibrary.isLoaded(id: CutsceneSpritesConfig.yodaID) == false)
        #expect(session.cutsceneVideo.player != nil)
    }

    @Test func sharedPickupIconsSurviveLevelScopedRelease() async {
        let session = await AppSession.loadResources()
        session.releaseLevelScopedAssets()
        #expect(session.spriteLibrary.uiImage(id: "coin") != nil)
        #expect(session.spriteLibrary.uiImage(id: "health") != nil)
        #expect(session.spriteLibrary.uiImage(id: "energy") != nil)
    }

    @Test func unownedTreasuresReleasedAfterLevelScopedRelease() async {
        let session = await AppSession.loadResources()
        let selectedTreasure = session.selectedLevel.treasure
        session.releaseLevelScopedAssets()
        for treasureID in LevelCatalog.loadFromBundle().compactMap(\.treasure) where treasureID != selectedTreasure {
            #expect(
                session.spriteLibrary.isLoaded(id: treasureID) == false,
                "Treasure \(treasureID) should not stay pinned after release"
            )
        }
        if let selectedTreasure {
            #expect(session.spriteLibrary.isLoaded(id: selectedTreasure))
        }
    }
}
