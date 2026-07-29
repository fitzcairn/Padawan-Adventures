import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct ConfigAuditTests {
    @Test func loadsEveryBundledConfigWithoutFallback() throws {
        let app = try WorldLoader.loadConfigFromBundle()
        try app.validate()
        #expect(app.display.tileWidth == 80)
        #expect(app.display.tileHeight == 49)

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

        for level in levels {
            #expect(!level.floor.set.isEmpty)
            let set = try FloorTileSet.loadFromBundle(set: level.floor.set)
            #expect(!set.floorTileIDs.isEmpty)

            #expect(!level.letters.set.isEmpty)
            let letterSet = try LetterSpriteSet.loadFromBundle(set: level.letters.set)
            #expect(letterSet.frames.count == 52)
            #expect(letterSet.missingKeys.isEmpty)

            let pitSet = try PitSpriteSet.loadFromBundle(set: level.floor.set)
            #expect(!pitSet.frames.isEmpty)
        }

        try ConfigAudit.run(
            app: app,
            levels: levels + [defaults],
            enemies: enemies,
            items: items,
            words: words,
            letters: letters,
            audio: audio,
            screens: screens,
            player: player
        )
    }

    @Test func badFloorSetFailsAudit() throws {
        let app = try WorldLoader.loadConfigFromBundle()
        let words = try WordCatalog.loadFromBundle()
        let letters = try LetterCatalog.loadFromBundle()
        var level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory,
            wordCatalog: words,
            letterCatalog: letters
        )
        level.floor.set = "does-not-exist"
        #expect(throws: ConfigAuditError.self) {
            try ConfigAudit.run(
                app: app,
                levels: [level],
                enemies: try EnemyConfig.loadFromBundle(),
                items: try ItemsConfig.loadFromBundle(),
                words: words,
                letters: letters,
                audio: try SoundSettings.loadFromBundle(),
                screens: try ScreensConfig.loadFromBundle(),
                player: try PlayerConfig.loadFromBundle()
            )
        }
    }

    @Test func badLetterSetFailsAudit() throws {
        let app = try WorldLoader.loadConfigFromBundle()
        let words = try WordCatalog.loadFromBundle()
        let letters = try LetterCatalog.loadFromBundle()
        var level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory,
            wordCatalog: words,
            letterCatalog: letters
        )
        level.letters.set = "does-not-exist"
        #expect(throws: ConfigAuditError.self) {
            try ConfigAudit.run(
                app: app,
                levels: [level],
                enemies: try EnemyConfig.loadFromBundle(),
                items: try ItemsConfig.loadFromBundle(),
                words: words,
                letters: letters,
                audio: try SoundSettings.loadFromBundle(),
                screens: try ScreensConfig.loadFromBundle(),
                player: try PlayerConfig.loadFromBundle()
            )
        }
    }

    @Test func misfiledMusicFailsAudit() throws {
        let app = try WorldLoader.loadConfigFromBundle()
        let words = try WordCatalog.loadFromBundle()
        let letters = try LetterCatalog.loadFromBundle()
        var level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory,
            wordCatalog: words,
            letterCatalog: letters
        )
        // timer-tick exists under Audio/FX only — must not satisfy a music cue.
        level.music = "timer-tick"
        #expect(throws: ConfigAuditError.self) {
            try ConfigAudit.run(
                app: app,
                levels: [level],
                enemies: try EnemyConfig.loadFromBundle(),
                items: try ItemsConfig.loadFromBundle(),
                words: words,
                letters: letters,
                audio: try SoundSettings.loadFromBundle(),
                screens: try ScreensConfig.loadFromBundle(),
                player: try PlayerConfig.loadFromBundle()
            )
        }
    }
}
