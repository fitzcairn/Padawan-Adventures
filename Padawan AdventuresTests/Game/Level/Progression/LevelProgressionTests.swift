import Foundation
import Testing
@testable import Padawan_Adventures

struct LevelProgressionTests {
    private let ordered = ["level_1", "level_2", "level_3"]

    @Test func nextUnlockedIndexStartsAtZero() {
        #expect(
            LevelProgression.nextUnlockedIndex(orderedLevels: ordered, completed: []) == 0
        )
    }

    @Test func nextUnlockedIndexAdvancesPastCompleted() {
        #expect(
            LevelProgression.nextUnlockedIndex(
                orderedLevels: ordered,
                completed: ["level_1"]
            ) == 1
        )
        #expect(
            LevelProgression.nextUnlockedIndex(
                orderedLevels: ordered,
                completed: ["level_1", "level_2"]
            ) == 2
        )
    }

    @Test func nextUnlockedIndexIsCountWhenAllComplete() {
        #expect(
            LevelProgression.nextUnlockedIndex(
                orderedLevels: ordered,
                completed: Set(ordered)
            ) == 3
        )
    }

    @Test func unlockStateGatesBeyondNextLevel() {
        #expect(
            LevelProgression.unlockState(
                for: "level_1",
                orderedLevels: ordered,
                completed: [],
                dadModeUnlocked: false
            ) == .unlocked
        )
        #expect(
            LevelProgression.unlockState(
                for: "level_2",
                orderedLevels: ordered,
                completed: [],
                dadModeUnlocked: false
            ) == .locked
        )
        #expect(
            LevelProgression.unlockState(
                for: "level_1",
                orderedLevels: ordered,
                completed: ["level_1"],
                dadModeUnlocked: false
            ) == .completed
        )
        #expect(
            LevelProgression.unlockState(
                for: "level_2",
                orderedLevels: ordered,
                completed: ["level_1"],
                dadModeUnlocked: false
            ) == .unlocked
        )
        #expect(
            LevelProgression.unlockState(
                for: "level_3",
                orderedLevels: ordered,
                completed: ["level_1"],
                dadModeUnlocked: false
            ) == .locked
        )
    }

    @Test func dadModeMakesAllIncompleteLevelsUnlocked() {
        #expect(
            LevelProgression.unlockState(
                for: "level_3",
                orderedLevels: ordered,
                completed: [],
                dadModeUnlocked: true
            ) == .unlocked
        )
        #expect(
            LevelProgression.unlockState(
                for: "level_1",
                orderedLevels: ordered,
                completed: ["level_1"],
                dadModeUnlocked: true
            ) == .completed
        )
        #expect(
            LevelProgression.isPlayable(
                for: "level_3",
                orderedLevels: ordered,
                completed: [],
                dadModeUnlocked: true
            )
        )
    }
}
