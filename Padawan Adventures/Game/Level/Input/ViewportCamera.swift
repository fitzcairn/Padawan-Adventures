import CoreGraphics
import Foundation

/// Follows the player until the user pans, then holds that viewport until a
/// destination tap, when it glides back to the player sprite.
struct ViewportCamera: Sendable {
    static let recenterDuration: TimeInterval = 0.5

    private enum Mode: Equatable {
        case following
        case free
        case recentering(elapsed: TimeInterval, startFocus: CGPoint)
    }

    private var mode: Mode = .following

    /// True while the camera should keep the player in the deadzone.
    var followsPlayer: Bool {
        if case .following = mode { return true }
        return false
    }

    /// A user pan parks the viewport; deadzone follow stays off until a destination tap.
    mutating func noteUserPan() {
        mode = .free
    }

    /// Starts a smooth return to the player after a destination tap, if the camera is parked.
    mutating func noteDestinationChosen(from focus: CGPoint) {
        guard !followsPlayer else { return }
        mode = .recentering(elapsed: 0, startFocus: focus)
    }

    /// Instantly resumes player follow (story change, encounter restore, tutorial end).
    mutating func snapToFollowing() {
        mode = .following
    }

    /// Advances a recenter glide toward `playerFocus`. Returns the new focus, or
    /// `nil` when the camera is not recentering.
    mutating func advance(deltaTime: TimeInterval, playerFocus: CGPoint) -> CGPoint? {
        guard case .recentering(let elapsed, let startFocus) = mode else { return nil }

        let nextElapsed = max(0, elapsed + deltaTime)
        if nextElapsed >= Self.recenterDuration {
            mode = .following
            return playerFocus
        }

        mode = .recentering(elapsed: nextElapsed, startFocus: startFocus)
        let progress = CGFloat(nextElapsed / Self.recenterDuration)
        return IsometricMath.interpolatedFocus(from: startFocus, to: playerFocus, progress: progress)
    }
}
