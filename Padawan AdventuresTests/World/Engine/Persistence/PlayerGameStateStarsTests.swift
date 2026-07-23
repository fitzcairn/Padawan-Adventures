import Foundation
import Testing
@testable import Padawan_Adventures

struct PlayerGameStateStarsTests {
    @Test func resetLevelStarsCurrentZerosInProgressCount() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStar("level_1")
        state.addLevelStar("level_1")
        #expect(state.levels["level_1"]?.starsCurrent == 2)

        state.resetLevelStarsCurrent("level_1")
        #expect(state.levels["level_1"]?.starsCurrent == 0)
        #expect(state.levels["level_1"]?.starsEarned == 0)
    }

    @Test func addLevelStarsAddsCountInOneStep() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStars("level_1", count: 10)
        #expect(state.levels["level_1"]?.starsCurrent == 10)

        state.addLevelStars("level_1", count: 0)
        #expect(state.levels["level_1"]?.starsCurrent == 10)
    }

    @Test func finalizeLevelStarsBanksFirstScoreIntoTotal() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.addLevelStar("level_1")
        state.addLevelStar("level_1")
        state.addLevelStar("level_1")

        let result = state.finalizeLevelStars("level_1")
        #expect(result.didBeatPrevious == true)
        #expect(result.previousBest == 0)
        #expect(result.newScore == 3)
        #expect(state.levels["level_1"]?.starsEarned == 3)
        #expect(state.totalStars == 3)
    }

    @Test func finalizeLevelStarsAddsOnlyImprovementDelta() {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 5)
        state.levels["level_1"] = LevelProgress(starsEarned: 5, starsCurrent: 8)

        let result = state.finalizeLevelStars("level_1")
        #expect(result.didBeatPrevious == true)
        #expect(result.previousBest == 5)
        #expect(result.newScore == 8)
        #expect(state.levels["level_1"]?.starsEarned == 8)
        #expect(state.totalStars == 8)
    }

    @Test func finalizeLevelStarsDoesNotChangeTotalWhenNotBeaten() {
        var state = PlayerGameState(health: 3, energy: 2, totalStars: 7)
        state.levels["level_1"] = LevelProgress(starsEarned: 7, starsCurrent: 4)

        let result = state.finalizeLevelStars("level_1")
        #expect(result.didBeatPrevious == false)
        #expect(result.previousBest == 7)
        #expect(result.newScore == 4)
        #expect(state.levels["level_1"]?.starsEarned == 7)
        #expect(state.totalStars == 7)
    }

    @Test func markLevelCompletedAddsArtifactOnce() {
        var state = PlayerGameState(health: 3, energy: 2)
        state.markLevelCompleted("level_1", artifact: "key.fill")
        state.markLevelCompleted("level_1", artifact: "key.fill")
        state.markLevelCompleted("level_2", artifact: "crown.fill")

        #expect(state.levels["level_1"]?.completed == true)
        #expect(state.levels["level_2"]?.completed == true)
        #expect(state.inventory.artifacts == ["key.fill", "crown.fill"])
    }

    @Test func inventoryAddArtifactIgnoresEmptyAndDuplicates() {
        var inventory = PlayerInventory()
        inventory.addArtifact("")
        inventory.addArtifact("key.fill")
        inventory.addArtifact("key.fill")
        inventory.addArtifact("sparkles")

        #expect(inventory.artifacts == ["key.fill", "sparkles"])
    }

    @Test func resetForNewGameClearsProgressAndRestoresVitals() {
        var state = PlayerGameState(health: 1, energy: 1, totalStars: 9)
        state.markLevelCompleted("level_1", artifact: "key.fill")
        state.levels["level_1"]?.starsEarned = 5
        state.levels["level_1"]?.starsCurrent = 2
        state.lastLevelStarted = "level_1"
        state.stats.enemiesKilled = 3

        state.resetForNewGame(health: 5, energy: 4)

        #expect(state.inventory.artifacts.isEmpty)
        #expect(state.totalStars == 0)
        #expect(state.levels.isEmpty)
        #expect(state.lastLevelStarted == nil)
        #expect(state.health == 5)
        #expect(state.energy == 4)
        #expect(state.stats.enemiesKilled == 3)
    }
}
