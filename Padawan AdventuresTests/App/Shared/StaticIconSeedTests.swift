import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct StaticIconSeedTests {
    @Test func scoreCoinSeedIgnoresNil() {
        // Force a known-good seed first so a subsequent nil cannot clear it.
        let existing = ScoreCoinIcon.uiImage()
        #expect(existing != nil)
        ScoreCoinIcon.seed(nil)
        #expect(ScoreCoinIcon.uiImage() != nil)
    }

    @Test func hudVitalSeedIgnoresNil() {
        let existing = HudVitalIcon.health.uiImage()
        #expect(existing != nil)
        HudVitalIcon.health.seed(nil)
        #expect(HudVitalIcon.health.uiImage() != nil)
    }
}
