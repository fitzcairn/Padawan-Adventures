import Testing
@testable import Padawan_Adventures

struct ScreenConfigTests {
    @Test func decodesMusicField() throws {
        let config = try ScreenConfig.decode(from: """
            music: title_menu
            """)
        #expect(config.music == "title_menu")
        #expect(config.musicCue == .track("title_menu"))
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
        #expect(config.musicCue == .track("title_menu"))
    }

    @Test func loadsYouWinScreenFromBundle() throws {
        let config = try ScreenConfig.loadFromBundle(named: "you_win")
        #expect(config.musicCue == .track("victory"))
    }

    @Test func loadsSettingsScreenFromBundle() throws {
        let config = try ScreenConfig.loadFromBundle(named: "settings")
        #expect(config.musicCue == .track("title_menu"))
    }

    @Test func loadsDefeatScreenFromBundle() throws {
        let config = try ScreenConfig.loadFromBundle(named: "defeat")
        #expect(config.musicCue == .silence)
    }

    @Test func loadsLevelSelectScreenMusicFromScreensYAML() throws {
        let config = try ScreenConfig.loadFromBundle(named: "level_select")
        #expect(config.musicCue == .track("level_screen"))
    }

    @Test func loadsLoadingScreenMusicFromScreensYAML() throws {
        let config = try ScreenConfig.loadFromBundle(named: "loading")
        #expect(config.musicCue == .track("title_menu"))
    }

    @Test func decodesBackgroundField() throws {
        let config = try ScreenConfig.decode(from: """
            music: title_menu
            background: level_screen_bg
            """)
        #expect(config.background == "level_screen_bg")
    }

    @Test func omittedBackgroundIsNil() throws {
        let config = try ScreenConfig.decode(from: """
            music: title_menu
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
        #expect(all.screens["menu"]?.musicCue == .track("title_menu"))
        #expect(all.screens["loading"]?.musicCue == .track("title_menu"))
        #expect(all.screens["preparing"]?.musicCue == .unchanged)
        #expect(all.screens["cutscene"]?.musicCue == .silence)
        #expect(all.screens["level_select"]?.musicCue == .track("level_screen"))
        #expect(all.screens["level_select"]?.background == "level_screen_bg")
        #expect(all.screens.count == 10)
    }

    @Test func missingScreenNameThrows() {
        #expect(throws: ConfigError.missingResource(file: "screens.yaml#does_not_exist")) {
            try ScreenConfig.loadFromBundle(named: "does_not_exist")
        }
    }
}
