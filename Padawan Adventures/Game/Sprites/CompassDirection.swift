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

    /// Eight-way facing from `from` toward `toward` using iso screen axes
    /// `screenX ∝ (x - y)`, `screenY ∝ -(x + y)`.
    static func facing(from: GridCoord, toward: GridCoord) -> CompassDirection {
        let dx = toward.x - from.x
        let dy = toward.y - from.y
        let screenX = Double(dx - dy)
        let screenY = Double(-(dx + dy))
        guard screenX != 0 || screenY != 0 else { return .down }

        // `atan2(screenX, screenY)` is 0 at screen-up and increases toward screen-right.
        let angle = atan2(screenX, screenY)
        let twoPi = Double.pi * 2
        let normalized = (angle + twoPi).truncatingRemainder(dividingBy: twoPi)
        let sector = Int((normalized + .pi / 8) / (.pi / 4)) % 8
        switch sector {
        case 0: return .up
        case 1: return .northeast
        case 2: return .right
        case 3: return .southeast
        case 4: return .down
        case 5: return .southwest
        case 6: return .left
        default: return .northwest
        }
    }
}

nonisolated enum SpriteLocomotion: String, Sendable {
    case idle
    case walk
}
