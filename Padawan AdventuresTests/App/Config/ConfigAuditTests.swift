import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct ConfigAuditTests {
    @Test func loadsEveryBundledConfigWithoutFallback() throws {
        let app = try WorldLoader.loadConfigFromBundle()
        try app.validate()

        let audio = try SoundSettings.loadFromBundle()
        try audio.validate()

        let player = try PlayerConfig.loadFromBundle()
        try player.validate()

        let hud = try HudConfig.loadFromBundle()
        try hud.validate()

        let screens = try ScreensConfig.loadFromBundle()
        #expect(!screens.screens.isEmpty)

        let enemies = try EnemyConfig.loadFromBundle()
        try enemies.validate()

        let items = try ItemsConfig.loadFromBundle()
        try items.validate()

        let terrain = try TerrainCatalog.loadFromBundle()
        #expect(!terrain.terrains.isEmpty)

        let words = try WordCatalog.loadFromBundle()
        try words.validate()

        let letters = try LetterCatalog.loadFromBundle()
        try letters.validate()

        let descriptors = LevelCatalog.loadFromBundle()
        #expect(!descriptors.isEmpty)

        let levels = try descriptors.map { descriptor in
            try LevelConfig.loadFromBundle(
                named: descriptor.resourceName,
                subdirectory: LevelCatalog.subdirectory,
                wordCatalog: words,
                letterCatalog: letters
            )
        }

        let defaults = try LevelConfig.loadFromBundle(
            named: "_defaults",
            subdirectory: LevelCatalog.subdirectory,
            wordCatalog: words,
            letterCatalog: letters
        )

        try ConfigAudit.run(
            app: app,
            levels: levels + [defaults],
            enemies: enemies,
            terrain: terrain,
            items: items,
            words: words,
            letters: letters,
            audio: audio,
            screens: screens,
            player: player
        )
    }
}
