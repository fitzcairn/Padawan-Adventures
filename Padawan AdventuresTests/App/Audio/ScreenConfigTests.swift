import Testing
@testable import Padawan_Adventures

struct ScreenConfigTests {
    @Test func decodesMusicField() throws {
        let config = try ScreenConfig.decode(from: """
            music: menu_theme
            """)
        #expect(config.music == "menu_theme")
        #expect(config.musicCue == .track("menu_theme"))
    }

    @Test func decodesNoneAsUnchangedCue() throws {
        let config = try ScreenConfig.decode(from: """
            music: none
            """)
        #expect(config.musicCue == .unchanged)
    }

    @Test func omittedMusicIsUnchanged() throws {
        let config = try ScreenConfig.decode(from: "{}\n")
        #expect(config.music == nil)
        #expect(config.musicCue == .unchanged)
    }

    @Test func loadsMenuScreenFromBundle() throws {
        let config = try ScreenConfig.loadFromBundle(named: "menu")
        #expect(config.musicCue == .track("menu_theme"))
    }

    @Test func loadsYouWinScreenFromBundle() throws {
        let config = try ScreenConfig.loadFromBundle(named: "you_win")
        #expect(config.musicCue == .track("victory"))
    }

    @Test func loadsSettingsScreenFromBundle() throws {
        let config = try ScreenConfig.loadFromBundle(named: "settings")
        #expect(config.musicCue == .track("menu_theme"))
    }

    @Test func loadsDefeatScreenFromBundle() throws {
        let config = try ScreenConfig.loadFromBundle(named: "defeat")
        #expect(config.musicCue == .silence)
    }

    @Test func loadsLevelSelectScreenMusicFromScreensYAML() throws {
        let config = try ScreenConfig.loadFromBundle(named: "level_select")
        #expect(config.musicCue == .track("menu_theme"))
    }

    @Test func decodesBackgroundField() throws {
        let config = try ScreenConfig.decode(from: """
            music: menu_theme
            background: level_screen_bg
            """)
        #expect(config.background == "level_screen_bg")
    }

    @Test func omittedBackgroundIsNil() throws {
        let config = try ScreenConfig.decode(from: """
            music: menu_theme
            """)
        #expect(config.background == nil)
    }

    @Test func loadsLevelSelectScreenBackground() throws {
        let config = try ScreenConfig.loadFromBundle(named: "level_select")
        #expect(config.background == "level_screen_bg")
    }

    @Test func loadsBundledScreensYAML() throws {
        let all = try ScreensConfig.loadFromBundle()
        #expect(all.version == 1)
        #expect(all.screens["menu"]?.musicCue == .track("menu_theme"))
        #expect(all.screens["loading"]?.musicCue == .unchanged)
        #expect(all.screens["preparing"]?.musicCue == .unchanged)
        #expect(all.screens["level_select"]?.background == "level_screen_bg")
        #expect(all.screens.count == 9)
    }

    @Test func missingScreenNameThrows() {
        #expect(throws: ConfigError.missingResource(file: "screens.yaml#does_not_exist")) {
            try ScreenConfig.loadFromBundle(named: "does_not_exist")
        }
    }
}
