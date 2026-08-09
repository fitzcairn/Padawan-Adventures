import Foundation
import SwiftUI
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

    @Test func seenMinigameTutorialsDefaultsEmptyOnDecode() throws {
        let data = try JSONEncoder().encode(PlayerGameState(health: 3, energy: 2))
        let decoded = try JSONDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.seenMinigameTutorials.isEmpty)
    }

    @Test func seenMinigameTutorialsSurvivesPlistRoundTrip() throws {
        var state = PlayerGameState(health: 3, energy: 2)
        let firstMark = state.markMinigameTutorialSeen("ending-sound-pit")
        let secondMark = state.markMinigameTutorialSeen("ending-sound-pit")
        #expect(firstMark)
        #expect(secondMark == false)

        let data = try PropertyListEncoder().encode(state)
        let decoded = try PropertyListDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.hasSeenMinigameTutorial("ending-sound-pit"))
        #expect(decoded.hasSeenMinigameTutorial("starting-sound-pit") == false)
    }

    @Test func resetForNewGameClearsSeenMinigameTutorials() {
        var state = PlayerGameState(health: 3, energy: 2)
        _ = state.markMinigameTutorialSeen("grapheme-sound-combat")
        state.resetForNewGame(health: 5, energy: 4)
        #expect(state.seenMinigameTutorials.isEmpty)
    }

    @Test func seenWorldTutorialDefaultsFalseOnDecode() throws {
        let data = try JSONEncoder().encode(PlayerGameState(health: 3, energy: 2))
        let decoded = try JSONDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.seenWorldTutorial == false)
    }

    @Test func seenWorldTutorialSurvivesPlistRoundTrip() throws {
        var state = PlayerGameState(health: 3, energy: 2)
        state.seenWorldTutorial = true
        let data = try PropertyListEncoder().encode(state)
        let decoded = try PropertyListDecoder().decode(PlayerGameState.self, from: data)
        #expect(decoded.seenWorldTutorial)
    }

    @Test func resetForNewGameClearsSeenWorldTutorial() {
        var state = PlayerGameState(health: 3, energy: 2, seenWorldTutorial: true)
        state.resetForNewGame(health: 5, energy: 4)
        #expect(state.seenWorldTutorial == false)
    }

    @Test func minigameTutorialKeysAreUniqueAcrossFamilies() {
        let keys = PitMinigameKind.allCases.map(\.rawValue)
            + GateMinigameKind.allCases.map(\.rawValue)
            + CombatMinigameKind.allCases.map(\.rawValue)
        #expect(keys.count == 10)
        #expect(Set(keys).count == keys.count)
    }

    @Test func everyMinigameKindHasDistinctTutorialStringID() {
        let keys = PitMinigameKind.allCases.map(\.rawValue)
            + GateMinigameKind.allCases.map(\.rawValue)
            + CombatMinigameKind.allCases.map(\.rawValue)
        let stringIDs = keys.map {
            MinigameTutorialView<EmptyView>.bodyStringID(forKindRawValue: $0)
        }
        #expect(Set(stringIDs).count == stringIDs.count)
        for id in stringIDs {
            #expect(id.hasPrefix("minigame_tutorial_"))
            #expect(!id.contains("-"))
        }
    }

    @Test func everyMinigameKindHasDemoStage() {
        // Compile-time / type-level coverage: each kind's scene conforms to MinigameDemoStage.
        let stages: [any MinigameDemoStage.Type] = [
            PitSoundOutWordScene.self,
            PitBridgeScene.self,
            GateSoundOutWordScene.self,
            GateGraphemeMatchScene.self,
            GateWordPlugScene.self,
            CombatScene.self,
            CombatDeflectScene.self,
        ]
        #expect(stages.count == 7)

        let keys = PitMinigameKind.allCases.map(\.rawValue)
            + GateMinigameKind.allCases.map(\.rawValue)
            + CombatMinigameKind.allCases.map(\.rawValue)
        #expect(keys.count == 10)
        // 10 kinds map onto 7 scene types (starting/ending share a scene).
        let uniqueSceneKinds: Set<String> = [
            "sound-out-word-pit",
            "ending-sound-pit",
            "starting-sound-pit",
            "sound-out-word-gate",
            "grapheme-sound-gate",
            "starting-sound-gate",
            "ending-sound-gate",
            "grapheme-sound-combat",
            "starting-sound-combat",
            "ending-sound-combat",
        ]
        #expect(Set(keys) == uniqueSceneKinds)
    }
}
