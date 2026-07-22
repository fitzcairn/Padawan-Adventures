import Testing
@testable import Padawan_Adventures

struct MusicSettingsTests {
    @Test func decodesFadeSeconds() throws {
        let settings = try MusicSettings.decode(from: """
            fade_seconds: 1.5
            """)
        #expect(settings.fadeSeconds == 1.5)
    }

    @Test func validateRejectsNegativeFade() {
        let settings = MusicSettings(fadeSeconds: -1)
        #expect(throws: MusicConfigError.invalid("fade_seconds must be >= 0")) {
            try settings.validate()
        }
    }

    @Test func loadsFromBundle() throws {
        let settings = try MusicSettings.loadFromBundle()
        try settings.validate()
        #expect(settings.fadeSeconds == 1.0)
    }
}
