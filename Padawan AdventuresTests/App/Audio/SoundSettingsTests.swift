import Testing
@testable import Padawan_Adventures

struct SoundSettingsTests {
    @Test func decodesFadeSecondsAndCommonFx() throws {
        let settings = try SoundSettings.decode(from: """
            fade_seconds: 1.5
            fx:
              win: sfx_win_alt
              lose: sfx_lose_alt
            """)
        #expect(settings.fadeSeconds == 1.5)
        #expect(settings.fx.trackID(for: "win") == "sfx_win_alt")
        #expect(settings.fx.trackID(for: "lose") == "sfx_lose_alt")
    }

    @Test func decodeUsesFallbackCommonFxWhenOmitted() throws {
        let settings = try SoundSettings.decode(from: """
            fade_seconds: 0.5
            """)
        #expect(settings.fadeSeconds == 0.5)
        #expect(settings.fx.trackID(for: "win") == "win")
        #expect(settings.fx.trackID(for: "lose") == "lose")
        #expect(settings.fx.trackID(for: "error") == "error")
        #expect(settings.fx.trackID(for: "correct") == "correct")
        #expect(settings.fx.trackID(for: "artifact_appear") == "level-screen-artifact-appear")
    }

    @Test func validateRejectsNegativeFade() {
        let settings = SoundSettings(fadeSeconds: -1)
        #expect(throws: MusicConfigError.invalid("fade_seconds must be >= 0")) {
            try settings.validate()
        }
    }

    @Test func loadsFromBundle() throws {
        let settings = try SoundSettings.loadFromBundle()
        try settings.validate()
        #expect(settings.fadeSeconds == 1.0)
        #expect(settings.fx.trackID(for: "win") == "win")
        #expect(settings.fx.trackID(for: "lose") == "lose")
        #expect(settings.fx.trackID(for: "error") == "error")
        #expect(settings.fx.trackID(for: "correct") == "correct")
        #expect(settings.fx.trackID(for: "artifact_appear") == "level-screen-artifact-appear")
    }
}
