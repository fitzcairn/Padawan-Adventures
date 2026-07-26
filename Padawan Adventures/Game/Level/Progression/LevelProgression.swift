import Foundation

/// Visual / interaction state for a level button on the select screen.
nonisolated enum LevelUnlockState: Equatable, Sendable {
    case completed
    case unlocked
    case locked
}

/// Pure helpers for level-select progression gating.
nonisolated enum LevelProgression {
    /// Index of the first incomplete level in catalog order, or `orderedLevels.count` if all complete.
    static func nextUnlockedIndex(
        orderedLevels: [String],
        completed: Set<String>
    ) -> Int {
        orderedLevels.firstIndex { !completed.contains($0) } ?? orderedLevels.count
    }

    static func unlockState(
        for resourceName: String,
        orderedLevels: [String],
        completed: Set<String>,
        dadModeUnlocked: Bool
    ) -> LevelUnlockState {
        if completed.contains(resourceName) {
            return .completed
        }
        if dadModeUnlocked {
            return .unlocked
        }
        guard let index = orderedLevels.firstIndex(of: resourceName) else {
            return .locked
        }
        let next = nextUnlockedIndex(orderedLevels: orderedLevels, completed: completed)
        return index <= next ? .unlocked : .locked
    }

    static func isPlayable(
        for resourceName: String,
        orderedLevels: [String],
        completed: Set<String>,
        dadModeUnlocked: Bool
    ) -> Bool {
        unlockState(
            for: resourceName,
            orderedLevels: orderedLevels,
            completed: completed,
            dadModeUnlocked: dadModeUnlocked
        ) != .locked
    }

    /// Planet that becomes newly available after first-completing `completedResource`, if any.
    static func resourceUnlockedByCompleting(
        _ completedResource: String,
        orderedLevels: [String]
    ) -> String? {
        guard let index = orderedLevels.firstIndex(of: completedResource) else { return nil }
        let nextIndex = index + 1
        guard nextIndex < orderedLevels.count else { return nil }
        return orderedLevels[nextIndex]
    }
}
