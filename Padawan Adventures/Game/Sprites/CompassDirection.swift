import Foundation

/// Eight-way facing used for sprite animation keys.
/// Names match **on-screen** direction (iso projection), not raw grid north.
/// Cardinals use up/down/left/right; diagonals keep compass names.
nonisolated enum CompassDirection: String, CaseIterable, Sendable {
    case up
    case northeast
    case right
    case southeast
    case down
    case southwest
    case left
    case northwest

    /// Maps a grid step `(dx, dy)` to the on-screen facing that step produces.
    ///
    /// Iso: `screenX ∝ (x - y)`, `screenY ∝ -(x + y)` (up on screen = decreasing x+y).
    init?(dx: Int, dy: Int) {
        switch (dx, dy) {
        case (-1, -1): self = .up          // upper middle
        case (0, -1): self = .northeast    // upper right
        case (1, -1): self = .right        // right
        case (1, 0): self = .southeast     // lower right
        case (1, 1): self = .down          // lower middle
        case (0, 1): self = .southwest     // lower left
        case (-1, 1): self = .left         // left
        case (-1, 0): self = .northwest    // upper left
        default: return nil
        }
    }

    /// Grid step that moves toward this on-screen facing.
    var dx: Int {
        switch self {
        case .up, .northwest, .left: return -1
        case .northeast, .southwest: return 0
        case .right, .southeast, .down: return 1
        }
    }

    var dy: Int {
        switch self {
        case .up, .northeast, .right: return -1
        case .northwest, .southeast: return 0
        case .left, .southwest, .down: return 1
        }
    }

    func animationName(locomotion: SpriteLocomotion) -> String {
        "\(locomotion.rawValue)_\(rawValue)"
    }
}

nonisolated enum SpriteLocomotion: String, Sendable {
    case idle
    case walk
}
