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

    // MARK: - Level layout

    /// Wraps a throwaway `Levels/` tree in a bundle so layout mistakes can be provoked
    /// without them having to exist in the app.
    private func layoutFixture(
        _ folders: [String: [String]],
        loose: [String] = []
    ) throws -> Bundle {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("layout-\(UUID().uuidString)", isDirectory: true)
        let levelRoot = root.appendingPathComponent(ConfigPath.levelRoot, isDirectory: true)
        try FileManager.default.createDirectory(at: levelRoot, withIntermediateDirectories: true)
        for (folder, files) in folders {
            let directory = levelRoot.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            for file in files {
                try Data().write(to: directory.appendingPathComponent(file))
            }
        }
        for file in loose {
            try Data().write(to: levelRoot.appendingPathComponent(file))
        }
        return try #require(Bundle(url: root))
    }

    @Test func bundledLevelLayoutIsClean() {
        #expect(ConfigAudit.checkLevelLayout().isEmpty)
    }

    @Test func wellFormedLevelFolderPassesLayout() throws {
        let bundle = try layoutFixture(
            ["1-tython": ["level.yaml", "1-tython-floor-atlas.json", "1-emitter-atlas.json"]],
            loose: ["_defaults.yaml"]
        )
        #expect(ConfigAudit.checkLevelLayout(bundle: bundle).isEmpty)
    }

    /// Art dropped beside the level folders belongs to no level and would never load.
    @Test func strayFileBesideLevelFoldersFailsLayout() throws {
        let bundle = try layoutFixture(
            ["1-tython": ["level.yaml"]],
            loose: ["1-tython-floor-atlas.json"]
        )
        let problems = ConfigAudit.checkLevelLayout(bundle: bundle)
        #expect(problems.count == 1)
        #expect(problems.first?.contains("must live inside a level folder") == true)
    }

    @Test func levelFolderWithoutConfigFailsLayout() throws {
        let bundle = try layoutFixture(["9-endor": ["9-endor-floor-atlas.json"]])
        let problems = ConfigAudit.checkLevelLayout(bundle: bundle)
        #expect(problems.count == 1)
        #expect(problems.first?.contains("'9-endor' has no level.yaml") == true)
    }

    /// The copy-a-sibling-folder mistake: art still named after the level it came from.
    @Test func misprefixedLevelAssetFailsLayout() throws {
        let bundle = try layoutFixture([
            "9-endor": ["level.yaml", "1-tython-floor-atlas.json"]
        ])
        let problems = ConfigAudit.checkLevelLayout(bundle: bundle)
        #expect(problems.count == 1)
        #expect(problems.first?.contains("1-tython-floor-atlas.json") == true)
        #expect(problems.first?.contains("must start with '9-'") == true)
    }

    @Test func emptyLevelRootFailsLayout() throws {
        let bundle = try layoutFixture([:])
        #expect(!ConfigAudit.checkLevelLayout(bundle: bundle).isEmpty)
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
        // pit-jump exists under Audio/FX only — must not satisfy a music cue.
        level.music = "pit-jump"
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
