import Foundation

nonisolated enum MinigameOutcome: Equatable, Sendable {
    case won(starsAwarded: Int)
    case lost
    /// Player left early; world is unchanged (obstacle remains, no penalty).
    case abandoned
}
