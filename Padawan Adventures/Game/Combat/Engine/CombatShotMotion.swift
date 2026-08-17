import CoreGraphics
import Foundation

/// Inbound slash-combat projectile motion. Travel is parameterized by arc length
/// along the fan curve, with exponential ease-out so visual speed decays as
/// `e^{-k t}` from the enemy to the player.
nonisolated enum CombatShotMotion {
    /// Decay rate for path speed. `e^{k}` is the start/end speed ratio.
    static let inboundEaseK: CGFloat = 2.5
    /// Faster than path ease so letters are readable once they leave the enemy.
    static let inboundScaleEaseK: CGFloat = 4
    static let inboundStartScale: CGFloat = 0.35
    static let inboundEndScale: CGFloat = 1.15
    /// Inbound travel is this fraction of the configured `shot_travel_seconds` speed.
    static let inboundSpeedScale: CGFloat = 0.72
    /// Hit when remaining arc length is this fraction of the two visual radii.
    static let hitDistanceScale: CGFloat = 0.60
    static let arcLengthSamples: Int = 48

    /// Exponential ease-out: `s(t) = (1 - e^{-k t}) / (1 - e^{-k})`.
    static func easeOut(_ t: CGFloat, k: CGFloat = inboundEaseK) -> CGFloat {
        let t = min(max(t, 0), 1)
        let k = max(k, 0.0001)
        return (1 - exp(-k * t)) / (1 - exp(-k))
    }

    static func inboundScale(t: CGFloat) -> CGFloat {
        inboundStartScale + (inboundEndScale - inboundStartScale) * easeOut(t, k: inboundScaleEaseK)
    }

    static func cubicBezier(
        t: CGFloat,
        start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        end: CGPoint
    ) -> CGPoint {
        let t = min(max(t, 0), 1)
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * c1.x + c * c2.x + d * end.x,
            y: a * start.y + b * c1.y + c * c2.y + d * end.y
        )
    }

    /// Point at `fraction` of the curve's arc length (0 = start, 1 = end).
    static func pointAlongCubicBezier(
        fraction: CGFloat,
        start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        end: CGPoint,
        samples: Int = arcLengthSamples
    ) -> CGPoint {
        let f = min(max(fraction, 0), 1)
        let sampled = sampleCubicBezier(
            start: start, c1: c1, c2: c2, end: end, samples: samples
        )
        if f <= 0 { return start }
        if f >= 1 || sampled.total <= 0 { return end }

        let target = f * sampled.total
        for i in 1..<sampled.points.count {
            if sampled.lengths[i] >= target {
                let span = sampled.lengths[i] - sampled.lengths[i - 1]
                let u = span > 0 ? (target - sampled.lengths[i - 1]) / span : 1
                let a = sampled.points[i - 1]
                let b = sampled.points[i]
                return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            }
        }
        return end
    }

    static func cubicBezierArcLength(
        start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        end: CGPoint,
        samples: Int = arcLengthSamples
    ) -> CGFloat {
        sampleCubicBezier(start: start, c1: c1, c2: c2, end: end, samples: samples).total
    }

    /// Distance still to travel along the curve to the player center.
    static func remainingArcLength(fraction: CGFloat, total: CGFloat) -> CGFloat {
        (1 - min(max(fraction, 0), 1)) * max(total, 0)
    }

    /// True when remaining curve distance is within the two sprites' visual radii.
    static func projectileHitsPlayer(
        remainingArcLength: CGFloat,
        projectileRadius: CGFloat,
        playerRadius: CGFloat
    ) -> Bool {
        let reach = (max(projectileRadius, 0) + max(playerRadius, 0)) * hitDistanceScale
        return remainingArcLength <= reach
    }

    /// Normalized inbound clock, matching `CombatScene.pathProgress`.
    static func pathProgress(elapsed: Double, startedAt: Double, duration: Double) -> Double {
        min(1, max(0, (elapsed - startedAt) / max(duration, 0.05)))
    }

    /// Arc-length fraction along the inbound curve for clock progress `t`.
    /// `arcStart` is how far the sprite had already traveled when this segment began.
    static func inboundArcFraction(progress t: Double, arcStart: CGFloat) -> CGFloat {
        let start = min(max(arcStart, 0), 1)
        return start + (1 - start) * easeOut(CGFloat(min(max(t, 0), 1)))
    }

    /// Restarts the remaining inbound arc from the current point so the leftover
    /// distance plays with a fresh ease-out in `remaining / multiplier` seconds.
    /// Keeping the old `t` would stay in the slow tail and look like no speed-up.
    /// No-ops when already finished (`t >= 1`) or when `multiplier` would not speed up.
    static func accelerateRemainingSegment(
        elapsed: Double,
        startedAt: Double,
        duration: Double,
        arcStart: CGFloat,
        multiplier: Double
    ) -> (startedAt: Double, duration: Double, arcStart: CGFloat) {
        let t = pathProgress(elapsed: elapsed, startedAt: startedAt, duration: duration)
        guard t < 1, multiplier > 1 else {
            return (startedAt, duration, arcStart)
        }
        let currentArc = inboundArcFraction(progress: t, arcStart: arcStart)
        let remaining = duration * (1 - t)
        return (elapsed, remaining / multiplier, currentArc)
    }

    private static func sampleCubicBezier(
        start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        end: CGPoint,
        samples: Int
    ) -> (points: [CGPoint], lengths: [CGFloat], total: CGFloat) {
        let steps = max(samples, 2)
        var points: [CGPoint] = [start]
        var lengths: [CGFloat] = [0]
        var total: CGFloat = 0
        var previous = start
        for step in 1...steps {
            let point = cubicBezier(
                t: CGFloat(step) / CGFloat(steps),
                start: start,
                c1: c1,
                c2: c2,
                end: end
            )
            total += hypot(point.x - previous.x, point.y - previous.y)
            points.append(point)
            lengths.append(total)
            previous = point
        }
        return (points, lengths, total)
    }
}
