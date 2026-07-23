import Foundation
import Testing
@testable import Padawan_Adventures

struct PlayerGameStateProgressionTests {
    @Test func dadModeUnlockedDefaultsFalseOnDecode() throws {
        let data = try JSONEncoder().encode(PlayerGameState(health: 3, energy: 2))
        let decoded = try JSONDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.dadModeUnlocked == false)
    }

    @Test func resetForNewGameClearsDadMode() {
        var state = PlayerGameState(health: 3, energy: 2, dadModeUnlocked: true)
        state.resetForNewGame(health: 5, energy: 4)
        #expect(state.dadModeUnlocked == false)
    }

    @Test func applyProgressionJumpMarksPriorsAndClearsDadMode() {
        var state = PlayerGameState(health: 3, energy: 2, dadModeUnlocked: true)
        state.applyProgressionJump(
            upTo: "level_3",
            orderedLevels: ["level_1", "level_2", "level_3"],
            artifactsByResource: [
                "level_1": "key.fill",
                "level_2": "crown.fill",
                "level_3": "sparkles",
            ]
        )

        #expect(state.levels["level_1"]?.completed == true)
        #expect(state.levels["level_2"]?.completed == true)
        #expect(state.levels["level_3"]?.completed != true)
        #expect(state.inventory.artifacts == ["key.fill", "crown.fill"])
        #expect(state.dadModeUnlocked == false)
    }

    @Test func applyProgressionJumpToFirstLevelGrantsNothing() {
        var state = PlayerGameState(health: 3, energy: 2, dadModeUnlocked: true)
        state.applyProgressionJump(
            upTo: "level_1",
            orderedLevels: ["level_1", "level_2"],
            artifactsByResource: ["level_1": "key.fill"]
        )

        #expect(state.levels.isEmpty)
        #expect(state.inventory.artifacts.isEmpty)
        #expect(state.dadModeUnlocked == false)
    }
}
