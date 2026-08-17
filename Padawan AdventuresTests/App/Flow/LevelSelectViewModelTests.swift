import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct LevelSelectViewModelTests {
    private let ordered = ["level_1", "level_2", "level_3"]

    @Test func lastPlayedResourceNameIsNilWhenNeverStarted() {
        #expect(
            LevelSelectViewModel.lastPlayedResourceName(
                lastLevelStarted: nil,
                orderedLevels: ordered
            ) == nil
        )
    }

    @Test func lastPlayedResourceNameMatchesCatalogId() {
        #expect(
            LevelSelectViewModel.lastPlayedResourceName(
                lastLevelStarted: "level_2",
                orderedLevels: ordered
            ) == "level_2"
        )
    }

    @Test func lastPlayedResourceNameIsNilForStaleId() {
        #expect(
            LevelSelectViewModel.lastPlayedResourceName(
                lastLevelStarted: "missing-planet",
                orderedLevels: ordered
            ) == nil
        )
    }

    @Test func continueLaunchModeResumesSave() {
        #expect(LevelDetailMode.continueAdventure.launchMode == .continueSave)
        #expect(LevelDetailMode.firstStart.launchMode == .newGame)
        #expect(LevelDetailMode.replay(highestStars: 3).launchMode == .newGame)
    }
}
