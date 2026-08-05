import Testing
@testable import Padawan_Adventures

struct ScreenCrossFadeTests {
    @Test func durationIsPositive() {
        #expect(ScreenCrossFade.duration > 0)
    }

    @Test func worldFadeDurationIsPositive() {
        #expect(WorldFade.duration > 0)
    }
}
