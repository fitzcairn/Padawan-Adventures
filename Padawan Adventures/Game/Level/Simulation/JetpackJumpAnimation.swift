import Foundation

/// Timing and clip choice for the world-HUD jetpack hop.
nonisolated enum JetpackJumpAnimation {
    static let framesPerSecond = 15.0
    static let takeoffFrames = 0...12
    static let hoverFrames = 12...14
    static let landFrames = 14...24
    /// Idle ↔ jetpack dissolve length, in frames at `framesPerSecond`.
    static let crossfadeFrames = 4

    static var takeoffDuration: TimeInterval {
        Double(takeoffFrames.count) / framesPerSecond
    }

    static var hoverLoopDuration: TimeInterval {
        Double(hoverFrames.count) / framesPerSecond
    }

    static var landDuration: TimeInterval {
        Double(landFrames.count) / framesPerSecond
    }

    /// Takeoff + one hover loop + landing at 15 fps.
    static var duration: TimeInterval {
        takeoffDuration + hoverLoopDuration + landDuration
    }

    static var frameDuration: TimeInterval { 1 / framesPerSecond }

    static var crossfadeDuration: TimeInterval {
        Double(crossfadeFrames) / framesPerSecond
    }

    static func clipName(for facing: CompassDirection) -> String {
        switch facing {
        case .up, .northeast:
            return "jetpack_northeast"
        case .right, .southeast, .down:
            return "jetpack_southeast"
        case .northwest, .left:
            return "jetpack_northwest"
        case .southwest:
            return "jetpack_southwest"
        }
    }

    enum Phase: Equatable, Sendable {
        case takeoff
        case hover
        case land
    }

    static func phase(elapsed: TimeInterval, duration: TimeInterval) -> Phase {
        if elapsed < takeoffDuration { return .takeoff }
        let landStart = max(takeoffDuration, duration - landDuration)
        if elapsed < landStart { return .hover }
        return .land
    }

    /// After takeoff the hop has crested — draw the jumper in front of the gate.
    static func drawsInFrontOfGate(elapsed: TimeInterval, duration: TimeInterval) -> Bool {
        phase(elapsed: elapsed, duration: duration) != .takeoff
    }
}
