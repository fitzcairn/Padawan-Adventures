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

    @Test func loadsLevelSelectScreenMusicAlongsidePlanetSprites() throws {
        let config = try ScreenConfig.loadFromBundle(named: "level_select")
        #expect(config.musicCue == .track("menu_theme"))
    }

}

