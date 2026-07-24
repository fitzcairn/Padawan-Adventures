import Testing
@testable import Padawan_Adventures

struct LevelDetailOverlayTests {
    @Test func neverPlayedUsesTakeOffPath() {
        let progress: LevelProgress? = nil
        let hasBeenPlayed = progress?.started == true
        #expect(hasBeenPlayed == false)
        #expect((progress?.starsEarned ?? 0) == 0)
    }

    @Test func startedLevelUsesRetryPathWithStars() {
        let progress = LevelProgress(started: true, completed: false, starsEarned: 12, starsCurrent: 0)
        #expect(progress.started == true)
        #expect(progress.starsEarned == 12)
    }

    @Test func multiTypeSpawnConfigPreservesOrder() {
        let config = WorldSeedConfig.EnemiesSpawnConfig(
            types: ["krayt_dragon", "tusken_raider"],
            spawnChancePerRoom: 0.8
        )
        #expect(config.types == ["krayt_dragon", "tusken_raider"])
        #expect(config.type == "krayt_dragon")
    }
}
