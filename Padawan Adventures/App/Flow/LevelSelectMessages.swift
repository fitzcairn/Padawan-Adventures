import Foundation

enum LevelSelectMessage: Equatable {
    case completeCurrentFirst
    case dadModeUnlocked

    var stringID: String {
        switch self {
        case .completeCurrentFirst:
            return "level_locked"
        case .dadModeUnlocked:
            return "dad_mode_unlocked"
        }
    }

    var title: String {
        Strings.text(stringID)
    }

    var rootID: String {
        switch self {
        case .completeCurrentFirst:
            return "levelSelect.lockedOverlay"
        case .dadModeUnlocked:
            return "levelSelect.dadModeOverlay"
        }
    }

    var titleID: String {
        switch self {
        case .completeCurrentFirst:
            return "levelSelect.lockedOverlay.title"
        case .dadModeUnlocked:
            return "levelSelect.dadModeOverlay.title"
        }
    }
}
