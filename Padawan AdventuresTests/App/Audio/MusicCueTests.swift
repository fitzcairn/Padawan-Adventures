import Testing
@testable import Padawan_Adventures

struct MusicCueTests {
    @Test func parseOmittedAndEmptyAsUnchanged() {
        #expect(MusicCue.parse(nil) == .unchanged)
        #expect(MusicCue.parse("") == .unchanged)
        #expect(MusicCue.parse("   ") == .unchanged)
    }

    @Test func parseNoneAsUnchanged() {
        #expect(MusicCue.parse("none") == .unchanged)
        #expect(MusicCue.parse("NONE") == .unchanged)
        #expect(MusicCue.parse(" None ") == .unchanged)
    }

    @Test func parseSilence() {
        #expect(MusicCue.parse("silence") == .silence)
        #expect(MusicCue.parse("SILENCE") == .silence)
    }

    @Test func parseTrackPreservesBasenameCasing() {
        #expect(MusicCue.parse("menu_theme") == .track("menu_theme"))
        #expect(MusicCue.parse("Victory") == .track("Victory"))
    }
}
