import Foundation

enum LevelSelectMessage: Equatable {
    case completeCurrentFirst
    case dadModeUnlocked

    var title: String {
        switch self {
        case .completeCurrentFirst:
            return "Complete the current level first!"
        case .dadModeUnlocked:
            return "Dad mode unlocked!"
        }
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
