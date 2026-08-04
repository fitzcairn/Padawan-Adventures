import Foundation
import SpriteKit
import UIKit

extension AppSession {
    nonisolated static func fallbackAppConfig() -> AppConfig {
        AppConfig(
            version: 1,
            seed: nil,
            display: AppConfig.DisplayParams(tileWidth: 40, tileHeight: 40)
        )
    }

    /// Backward-compatible alias used by older test helpers.
    nonisolated static func fallbackConfig() -> AppConfig {
        fallbackAppConfig()
    }

    /// Creates player/save stores without trapping when Application Support is unavailable.
    private static func makePersistenceStores() -> (PlayerStateStore, GameSaveService) {
        func pair(at directory: URL?) -> (PlayerStateStore, GameSaveService)? {
            guard let store = try? PlayerStateStore(directoryURL: directory),
                  let save = try? GameSaveService(directoryURL: store.rootDirectoryURL) else {
                return nil
            }
            return (store, save)
        }

        if let stores = pair(at: nil) {
            return stores
        }

        var candidates: [URL] = [
            FileManager.default.temporaryDirectory
                .appendingPathComponent("PadawanAdventures", isDirectory: true),
        ]
        candidates.append(contentsOf: (0..<16).map { _ in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("PadawanAdventures-\(UUID().uuidString)", isDirectory: true)
        })

        for directory in candidates {
            if let stores = pair(at: directory) {
                GameLogger.fault(.session, "Persistence using fallback directory: \(directory.path)")
                return stores
            }
        }

        // Non-trapping last resort for transient I/O failures during bootstrap.
        while true {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("PadawanAdventures-\(UUID().uuidString)", isDirectory: true)
            if let stores = pair(at: directory) {
                GameLogger.fault(.session, "Persistence using extended fallback: \(directory.path)")
                return stores
            }
        }
    }

    /// Loads config, stores, and warms screen + shared gameplay assets before tap-to-start.
    ///
    /// Call after the loading screen has already warmed title art into `spriteLibrary`.
    /// `onProgress` receives a monotonically useful 0...1 fraction for this phase only.
    static func loadResources(
        spriteLibrary: SpriteLibrary? = nil,
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async -> AppSession {
        func report(_ value: Double) async {
            onProgress?(value)
            await Task.yield()
        }

        GameLogger.mark(.session, "loadResources begin")
        let spriteLibrary = spriteLibrary ?? SpriteLibrary()

        // Ensure title art is present when callers (tests) skip the LoadingView phase.
        if spriteLibrary.uiImage(id: "logo") == nil,
           let loadingSprites = try? LoadingSpritesConfig.loadFromBundle() {
            for entry in loadingSprites.entries {
                await spriteLibrary.ensureLoaded(entry.config, id: entry.id)
            }
            _ = spriteLibrary.uiImage(id: "logo")
            _ = spriteLibrary.uiImages(id: "kam")
            _ = spriteLibrary.uiImages(id: "yoda")
        }
        await report(0.02)

        // Config / store bootstrap, then remaining screen + gameplay assets.
        let configEnd = 0.14

        // Start title music early so it is audible during the rest of bootstrap.
        let soundSettings = ConfigStore.loadOrFallback("audio", fallback: SoundSettings.fallback) {
            let loaded = try SoundSettings.loadFromBundle()
            try loaded.validate()
            return loaded
        }
        BackgroundMusicController.shared.configure(fadeSeconds: soundSettings.fadeSeconds)
        SoundEffectsController.shared.configure(commonFx: soundSettings.fx)
        AudioPreferences.shared.applyToControllers()
        BackgroundMusicController.shared.applyScreen(named: "loading")
        await report(0.04)

        let appAndLevel = ConfigStore.loadOrFallback(
            "app+level",
            fallback: (fallbackAppConfig(), LevelConfig.fallback)
        ) { () -> (AppConfig, LevelConfig) in
            let loaded = try WorldLoader.loadConfigAndLevelFromBundle()
            try loaded.config.validate()
            return (loaded.config, loaded.level)
        }
        let appConfig = appAndLevel.0
        let selectedLevel = appAndLevel.1
        GameLogger.mark(
            .config,
            "bootstrap level '\(selectedLevel.name)' loaded (combat: \(selectedLevel.combat.minigames.map(\.kind.rawValue).joined(separator: "/")))"
        )
        await report(0.06)

        let playerConfig = ConfigStore.loadOrFallback("player", fallback: PlayerConfig.fallback) {
            let loaded = try PlayerConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        }
        // Warm shared + player FX so the first gameplay cue does not decode on the main thread.
        var warmTrackIDs = Array(soundSettings.fx.events.values)
        warmTrackIDs.append(contentsOf: playerConfig.fx.events.values)
        SoundEffectsController.shared.prepare(trackIDs: warmTrackIDs)

        let enemyConfig = ConfigStore.loadOrFallback("enemies", fallback: EnemyConfig.fallback) {
            let loaded = try EnemyConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        let itemsConfig = ConfigStore.loadOrFallback("items", fallback: ItemsConfig.fallback) {
            let loaded = try ItemsConfig.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        let screensConfig = ConfigStore.loadOrFallback("screens", fallback: ScreensConfig.fallback) {
            try ScreensConfig.loadFromBundle()
        }

        let wordCatalog = ConfigStore.loadOrFallback("words", fallback: WordCatalog.fallback) {
            let loaded = try WordCatalog.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        let letterCatalog = ConfigStore.loadOrFallback("phonics", fallback: LetterCatalog.fallback) {
            let loaded = try LetterCatalog.loadFromBundle()
            try loaded.validate()
            return loaded
        }

        await report(0.10)

        let (playerStore, saveService) = Self.makePersistenceStores()

        try? await playerStore.purgeOrphans()
        await report(configEnd)

        let backgroundLibrary = BackgroundLibrary()
        let levelDescriptors = LevelCatalog.loadFromBundle()

        // 1) Level-select planet art (+ upright UIImages for first paint).
        let uiEntries = levelDescriptors.compactMap { level -> (String, SpriteConfig)? in
            guard let sprite = level.sprite else { return nil }
            return (level.resourceName, sprite)
        }
        let planetsEnd = uiEntries.isEmpty ? configEnd : 0.28
        if !uiEntries.isEmpty {
            let total = uiEntries.count
            for (index, entry) in uiEntries.enumerated() {
                let start = LoadProgress.map(Double(index) / Double(total), from: configEnd, to: planetsEnd)
                let end = LoadProgress.map(Double(index + 1) / Double(total), from: configEnd, to: planetsEnd)
                await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
                _ = spriteLibrary.uiImage(id: entry.0, named: "idle")
            }
        }
        await report(planetsEnd)

        // 2) Screen backgrounds from screens.yaml.
        let screenBackgroundNames = BackgroundLibrary.screenBackgroundNames()
        let backgroundsEnd = screenBackgroundNames.isEmpty ? planetsEnd : 0.40
        await backgroundLibrary.ensureLoaded(names: screenBackgroundNames) { local in
            onProgress?(LoadProgress.map(local, from: planetsEnd, to: backgroundsEnd))
        }
        await report(backgroundsEnd)

        // 2b) Cutscene movie + characters, so NEW GAME opens on a running video.
        let cutsceneVideo = CutsceneVideo()
        let cutsceneEnd = 0.46
        await cutsceneVideo.preload()
        if let cutsceneSprites = try? CutsceneSpritesConfig.loadFromBundle() {
            let total = max(cutsceneSprites.entries.count, 1)
            for (index, entry) in cutsceneSprites.entries.enumerated() {
                let start = LoadProgress.map(
                    Double(index) / Double(total), from: backgroundsEnd, to: cutsceneEnd
                )
                let end = LoadProgress.map(
                    Double(index + 1) / Double(total), from: backgroundsEnd, to: cutsceneEnd
                )
                await spriteLibrary.ensureLoaded(entry.config, id: entry.id) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
                _ = spriteLibrary.uiImages(id: entry.id)
            }
        }
        await report(cutsceneEnd)

        // 3) (Treasure / coin / HUD icons seed after item sprites load in step 5.)
        let iconsEnd = cutsceneEnd
        await report(iconsEnd)

        // 4) Player walk / combat sprites.
        let playerEnd = 0.58
        if let sprite = playerConfig.sprite {
            await spriteLibrary.ensureLoaded(sprite, id: "player") { local in
                onProgress?(LoadProgress.map(local, from: iconsEnd, to: 0.54))
            }
        }
        if let combat = playerConfig.combatSprite {
            await spriteLibrary.ensureLoaded(combat, id: "player_combat") { local in
                onProgress?(LoadProgress.map(local, from: 0.54, to: playerEnd))
            }
        }
        await report(playerEnd)

        // 5) Shared pickups + coin + the bootstrap level's treasure part only.
        var itemIDs: Set<String> = [
            PickupKind.health.rawValue,
            PickupKind.energy.rawValue,
            PickupKind.treasure.rawValue,
            "coin",
        ]
        if let treasureID = selectedLevel.treasure {
            itemIDs.insert(treasureID)
        }
        let itemEntries = itemsConfig.items
            .filter { itemIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
            .compactMap { id, item -> (String, SpriteConfig)? in
                guard let sprite = item.sprite else { return nil }
                return (id, sprite)
            }
        let itemsEnd = itemEntries.isEmpty ? playerEnd : 0.70
        if !itemEntries.isEmpty {
            let total = itemEntries.count
            for (index, entry) in itemEntries.enumerated() {
                let start = LoadProgress.map(Double(index) / Double(total), from: playerEnd, to: itemsEnd)
                let end = LoadProgress.map(Double(index + 1) / Double(total), from: playerEnd, to: itemsEnd)
                await spriteLibrary.ensureLoaded(entry.1, id: entry.0) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
            }
        }
        ScoreCoinIcon.seed(spriteLibrary.uiImage(id: "coin"))
        HudVitalIcon.health.seed(spriteLibrary.uiImage(id: "health"))
        HudVitalIcon.energy.seed(spriteLibrary.uiImage(id: "energy"))
        await report(itemsEnd)

        // 6) Enemy sprites used by any playable level (not the entire unused catalog).
        let levelsForAudit: [LevelConfig]
        do {
            levelsForAudit = try levelDescriptors.map { descriptor in
                try LevelConfig.loadFromBundle(
                    named: descriptor.resourceName,
                    subdirectory: LevelCatalog.subdirectory,
                    wordCatalog: wordCatalog,
                    letterCatalog: letterCatalog
                )
            }
        } catch {
            levelsForAudit = [selectedLevel]
            GameLogger.fault(.config, "failed to load levels during bootstrap: \(error)")
            assertionFailure("Failed to load levels during bootstrap: \(error)")
        }

        var enemySpriteIDs = Set<String>()
        for level in levelsForAudit {
            for typeID in level.enemies?.types ?? [] {
                if let spriteID = enemyConfig.enemies[typeID]?.sprite {
                    enemySpriteIDs.insert(spriteID)
                }
            }
        }
        let enemyEntries = enemyConfig.sprites
            .filter { enemySpriteIDs.contains($0.key) }
            .sorted { $0.key < $1.key }
        let enemiesEnd = enemyEntries.isEmpty ? itemsEnd : 0.92
        if !enemyEntries.isEmpty {
            let total = enemyEntries.count
            for (index, entry) in enemyEntries.enumerated() {
                let start = LoadProgress.map(Double(index) / Double(total), from: itemsEnd, to: enemiesEnd)
                let end = LoadProgress.map(Double(index + 1) / Double(total), from: itemsEnd, to: enemiesEnd)
                await spriteLibrary.ensureLoaded(entry.value, id: entry.key) { local in
                    onProgress?(LoadProgress.map(local, from: start, to: end))
                }
            }
        }
        await report(enemiesEnd)

        // 7) Gate minigame stills + GPU upload for every warmed texture.
        var gateTextures = GateMinigameBackground.preloadTextures()
        if let capacitor = GateSpellingCapacitorSprites.load() {
            gateTextures.append(capacitor)
        }
        if let switches = GateLetterMatchSwitchSprites.load() {
            gateTextures.append(switches.off)
            gateTextures.append(switches.on)
        }
        if let sockets = GateWordPlugSocketSprites.load() {
            gateTextures.append(contentsOf: sockets)
        }
        if let plugs = GateWordPlugPlugSprites.load() {
            gateTextures.append(contentsOf: plugs)
        }
        let preloadTextures = spriteLibrary.allTextures() + gateTextures
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SKTexture.preload(preloadTextures) {
                continuation.resume()
            }
        }
        await report(1)

        // Floor / letter / pit / gate sets stay per-level (single active set in each library).
        let floorTileSetLibrary = FloorTileSetLibrary()
        let letterSpriteSetLibrary = LetterSpriteSetLibrary()
        let pitSpriteSetLibrary = PitSpriteSetLibrary()
        let gateSpriteSetLibrary = GateSpriteSetLibrary()

        do {
            try ConfigAudit.run(
                app: appConfig,
                levels: levelsForAudit,
                enemies: enemyConfig,
                items: itemsConfig,
                words: wordCatalog,
                letters: letterCatalog,
                audio: soundSettings,
                screens: screensConfig,
                player: playerConfig
            )
        } catch {
            GameLogger.fault(.config, "ConfigAudit failed: \(error)")
            assertionFailure("ConfigAudit failed: \(error)")
        }
        GameLogger.mark(.session, "loadResources complete")
        MemoryProbe.mark("loadResources-complete")

        return AppSession(
            appConfig: appConfig,
            selectedLevel: selectedLevel,
            playerConfig: playerConfig,
            enemyConfig: enemyConfig,
            itemsConfig: itemsConfig,
            playerStore: playerStore,
            saveService: saveService,
            hasCompatibleSave: false,
            spriteLibrary: spriteLibrary,
            floorTileSetLibrary: floorTileSetLibrary,
            letterSpriteSetLibrary: letterSpriteSetLibrary,
            pitSpriteSetLibrary: pitSpriteSetLibrary,
            gateSpriteSetLibrary: gateSpriteSetLibrary,
            backgroundLibrary: backgroundLibrary,
            cutsceneVideo: cutsceneVideo,
            retainedEnemySpriteIDs: enemySpriteIDs
        )
    }
}
