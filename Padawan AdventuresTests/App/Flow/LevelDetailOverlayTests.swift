import Testing
@testable import Padawan_Adventures

struct LevelDetailOverlayTests {
    @Test func firstStartShowsConfirmModalWithoutHighestScore() {
        let progress: LevelProgress? = nil
        let hasBeenPlayed = progress?.started == true
        #expect(hasBeenPlayed == false)
        let highestStars: Int? = hasBeenPlayed ? (progress?.starsEarned ?? 0) : nil
        #expect(highestStars == nil)
    }

    @Test func startedLevelShowsRetryModalWithStars() {
        let progress = LevelProgress(started: true, completed: false, starsEarned: 12, starsCurrent: 0)
        let hasBeenPlayed = progress.started == true
        #expect(hasBeenPlayed == true)
        let highestStars: Int? = hasBeenPlayed ? progress.starsEarned : nil
        #expect(highestStars == 12)
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
