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

    @Test func seenMinigameInstructionsDefaultsEmptyOnDecode() throws {
        let data = try JSONEncoder().encode(PlayerGameState(health: 3, energy: 2))
        let decoded = try JSONDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.seenMinigameInstructions.isEmpty)
    }

    @Test func seenMinigameInstructionsSurvivesPlistRoundTrip() throws {
        var state = PlayerGameState(health: 3, energy: 2)
        let firstMark = state.markMinigameInstructionsSeen("ending-sound-pit")
        let secondMark = state.markMinigameInstructionsSeen("ending-sound-pit")
        #expect(firstMark)
        #expect(secondMark == false)

        let data = try PropertyListEncoder().encode(state)
        let decoded = try PropertyListDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.hasSeenMinigameInstructions("ending-sound-pit"))
        #expect(decoded.hasSeenMinigameInstructions("starting-sound-pit") == false)
    }

    @Test func resetForNewGameClearsSeenMinigameInstructions() {
        var state = PlayerGameState(health: 3, energy: 2)
        _ = state.markMinigameInstructionsSeen("grapheme-sound-combat")
        state.resetForNewGame(health: 5, energy: 4)
        #expect(state.seenMinigameInstructions.isEmpty)
    }

    @Test func minigameInstructionKeysAreUniqueAcrossFamilies() {
        let keys = PitMinigameKind.allCases.map(\.rawValue)
            + GateMinigameKind.allCases.map(\.rawValue)
            + CombatMinigameKind.allCases.map(\.rawValue)
        #expect(keys.count == 10)
        #expect(Set(keys).count == keys.count)
    }

    @Test func everyMinigameKindHasDistinctInstructionsStringID() {
        let keys = PitMinigameKind.allCases.map(\.rawValue)
            + GateMinigameKind.allCases.map(\.rawValue)
            + CombatMinigameKind.allCases.map(\.rawValue)
        let stringIDs = keys.map { MinigameInstructionsView.bodyStringID(forKindRawValue: $0) }
        #expect(Set(stringIDs).count == stringIDs.count)
        for id in stringIDs {
            #expect(id.hasPrefix("minigame_instructions_"))
            #expect(!id.contains("-"))
        }
    }
}
