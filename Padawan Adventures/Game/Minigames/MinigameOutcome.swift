import Foundation

nonisolated enum MinigameOutcome: Equatable, Sendable {
    case won(starsAwarded: Int)
    case lost
}
