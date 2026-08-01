import Foundation
import UIKit

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
        progressionEpoch: Int,
        nameSpeaker: LevelNameSpeaker
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

        nameSpeaker.speak(level.displayName)
        return nil
    }
}
