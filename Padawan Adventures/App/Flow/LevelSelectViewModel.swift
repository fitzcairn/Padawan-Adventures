import Foundation
import UIKit

enum LevelDetailMode: Equatable, Sendable {
    case firstStart
    case continueAdventure
    case replay(highestStars: Int)

    var launchMode: GameLaunchMode {
        switch self {
        case .continueAdventure: return .continueSave
        case .firstStart, .replay: return .newGame
        }
    }

    var promptSpeakID: String? {
        switch self {
        case .firstStart: return nil
        case .continueAdventure: return "level_detail_continue_prompt"
        case .replay: return "level_detail_replay_prompt"
        }
    }
}

@MainActor
struct LevelSelectViewModel {
    let session: AppSession
    let levels: [LevelDescriptor]

    var orderedResourceNames: [String] {
        levels.map(\.resourceName)
    }

    var completedLevels: Set<String> {
        let progress = session.playerState?.levels ?? [:]
        return Set(progress.compactMap { name, level in
            level.completed ? name : nil
        })
    }

    /// Playthrough wallet shown on every completed planet chip.
    var completedHighScores: [String: Int] {
        let wallet = session.playerState?.totalStars ?? 0
        let progress = session.playerState?.levels ?? [:]
        var scores: [String: Int] = [:]
        for (name, level) in progress where level.completed {
            scores[name] = wallet
        }
        return scores
    }

    nonisolated static func detailMode(
        resourceName: String,
        started: Bool,
        starsEarned: Int,
        hasCompatibleSave: Bool,
        lastLevelStarted: String?
    ) -> LevelDetailMode {
        if hasCompatibleSave, lastLevelStarted == resourceName {
            return .continueAdventure
        }
        if started {
            return .replay(highestStars: starsEarned)
        }
        return .firstStart
    }

    func detailMode(for resourceName: String) -> LevelDetailMode {
        let progress = session.playerState?.levels[resourceName]
        return Self.detailMode(
            resourceName: resourceName,
            started: progress?.started == true,
            starsEarned: session.playerState?.totalStars ?? 0,
            hasCompatibleSave: session.hasCompatibleSave,
            lastLevelStarted: session.playerState?.lastLevelStarted
        )
    }

    func inventoryLevels(progressionEpoch: Int) -> [LevelDescriptor] {
        _ = progressionEpoch
        let completed = completedLevels
        return levels.filter { completed.contains($0.resourceName) }
    }

    func dadModeUnlocked(progressionEpoch: Int) -> Bool {
        _ = progressionEpoch
        return session.isDadModeUnlocked
    }

    func inventoryTreasureIDs(progressionEpoch: Int) -> [String] {
        inventoryLevels(progressionEpoch: progressionEpoch).compactMap(\.treasure)
    }

    static func seededInventoryIcons(session: AppSession, levels: [LevelDescriptor]) -> [String: UIImage] {
        var seededIcons: [String: UIImage] = [:]
        for level in levels {
            if let id = level.treasure, let image = session.spriteLibrary.uiImage(id: id) {
                seededIcons[id] = image
            }
        }
        return seededIcons
    }

    static func planetsReady(session: AppSession, levels: [LevelDescriptor]) -> Bool {
        levels.allSatisfy { level in
            level.sprite == nil
                || session.spriteLibrary.uiImage(id: level.resourceName, named: "idle") != nil
        }
    }

    static func initialCelebrationUnlockResource(
        pending: String?,
        orderedLevels: [String]
    ) -> String? {
        pending.flatMap {
            LevelProgression.resourceUnlockedByCompleting($0, orderedLevels: orderedLevels)
        }
    }

    nonisolated static func lastPlayedResourceName(
        lastLevelStarted: String?,
        orderedLevels: [String]
    ) -> String? {
        guard let lastLevelStarted, orderedLevels.contains(lastLevelStarted) else { return nil }
        return lastLevelStarted
    }

    var lastPlayedResourceName: String? {
        Self.lastPlayedResourceName(
            lastLevelStarted: session.playerState?.lastLevelStarted,
            orderedLevels: orderedResourceNames
        )
    }

    func refreshInventoryIcons(ids: [String]) -> [String: UIImage] {
        var icons: [String: UIImage] = [:]
        for id in ids {
            if let image = session.spriteLibrary.uiImage(id: id) {
                icons[id] = image
            }
        }
        return icons
    }

    func handleLevelTap(
        _ level: LevelDescriptor,
        progressionEpoch: Int
    ) -> LevelSelectMessage? {
        let playable = LevelProgression.isPlayable(
            for: level.resourceName,
            orderedLevels: orderedResourceNames,
            completed: completedLevels,
            dadModeUnlocked: dadModeUnlocked(progressionEpoch: progressionEpoch)
        )
        guard playable else {
            return .completeCurrentFirst
        }

        return nil
    }
}
