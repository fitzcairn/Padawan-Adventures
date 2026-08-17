import Testing
@testable import Padawan_Adventures

struct LevelDetailOverlayTests {
    @Test func noSaveAndNotStartedIsFirstStart() {
        let mode = LevelSelectViewModel.detailMode(
            resourceName: "1-tython",
            started: false,
            starsEarned: 0,
            hasCompatibleSave: false,
            lastLevelStarted: nil
        )
        #expect(mode == .firstStart)
        #expect(mode.launchMode == .newGame)
        #expect(mode.promptSpeakID == nil)
    }

    @Test func noSaveAndStartedIsReplayWithBestCoins() {
        let mode = LevelSelectViewModel.detailMode(
            resourceName: "1-tython",
            started: true,
            starsEarned: 12,
            hasCompatibleSave: false,
            lastLevelStarted: "1-tython"
        )
        #expect(mode == .replay(highestStars: 12))
        #expect(mode.launchMode == .newGame)
        #expect(mode.promptSpeakID == "level_detail_replay_prompt")
    }

    @Test func saveForThisPlanetIsContinueEvenIfStarted() {
        let mode = LevelSelectViewModel.detailMode(
            resourceName: "1-tython",
            started: true,
            starsEarned: 8,
            hasCompatibleSave: true,
            lastLevelStarted: "1-tython"
        )
        #expect(mode == .continueAdventure)
        #expect(mode.launchMode == .continueSave)
        #expect(mode.promptSpeakID == "level_detail_continue_prompt")
    }

    @Test func saveForAnotherPlanetIsNotContinue() {
        let mode = LevelSelectViewModel.detailMode(
            resourceName: "2-tatooine",
            started: true,
            starsEarned: 4,
            hasCompatibleSave: true,
            lastLevelStarted: "1-tython"
        )
        #expect(mode == .replay(highestStars: 4))
        #expect(mode.launchMode == .newGame)
    }

    @Test func saveForAnotherUnstartedPlanetIsFirstStart() {
        let mode = LevelSelectViewModel.detailMode(
            resourceName: "2-tatooine",
            started: false,
            starsEarned: 0,
            hasCompatibleSave: true,
            lastLevelStarted: "1-tython"
        )
        #expect(mode == .firstStart)
    }

    @Test func replayPromptIsHighScoreLabel() {
        #expect(Strings.text("level_detail_replay_prompt") == "Your last high score:")
    }

    @Test func continuePromptInterpolatesPlanet() {
        #expect(
            Strings.text(
                "level_detail_continue_prompt",
                ["planet": "Tatooine"]
            ) == "Continue your adventure on Tatooine?"
        )
    }

    @Test func multiTypeSpawnConfigPreservesOrder() {
        let config = LevelConfig.EnemiesSpawnConfig(
            types: ["dino", "treant"],
            spawnChancePerRoom: 0.8
        )
        #expect(config.types == ["dino", "treant"])
        #expect(config.type == "dino")
    }
}
