import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct CombatShotMotionTests {
    @Test func easeOutPinsTheEndpoints() {
        #expect(abs(CombatShotMotion.easeOut(0)) < 0.0001)
        #expect(abs(CombatShotMotion.easeOut(1) - 1) < 0.0001)
        #expect(abs(CombatShotMotion.easeOut(-0.2)) < 0.0001)
        #expect(abs(CombatShotMotion.easeOut(1.4) - 1) < 0.0001)
    }

    @Test func easeOutLeadsLinear() {
        #expect(CombatShotMotion.easeOut(0.5) > 0.5)
    }

    @Test func easeOutSpeedDecaysExponentially() {
        let k = CombatShotMotion.inboundEaseK
        let dt: CGFloat = 0.05
        let expectedRatio = exp(-k * dt)
        for i in 0..<12 {
            let t = CGFloat(i) * dt
            let v0 = CombatShotMotion.easeOut(t + dt) - CombatShotMotion.easeOut(t)
            let v1 = CombatShotMotion.easeOut(t + 2 * dt) - CombatShotMotion.easeOut(t + dt)
            #expect(v0 > v1)
            #expect(abs(v1 / v0 - expectedRatio) < 0.04)
        }
    }

    @Test func inboundScalePinsTheEndpoints() {
        #expect(abs(CombatShotMotion.inboundScale(t: 0) - CombatShotMotion.inboundStartScale) < 0.0001)
        #expect(abs(CombatShotMotion.inboundScale(t: 1) - CombatShotMotion.inboundEndScale) < 0.0001)
    }

    @Test func inboundScaleGrowsFasterThanLinearEarly() {
        let scale = CombatShotMotion.inboundScale(t: 0.25)
        let linear = CombatShotMotion.inboundStartScale
            + (CombatShotMotion.inboundEndScale - CombatShotMotion.inboundStartScale) * 0.25
        #expect(scale > linear)
    }

    @Test func arcLengthPinsTheEndpoints() {
        let start = CGPoint(x: 10, y: 200)
        let c1 = CGPoint(x: 80, y: 140)
        let c2 = CGPoint(x: 40, y: 80)
        let end = CGPoint(x: 20, y: 20)
        let a = CombatShotMotion.pointAlongCubicBezier(
            fraction: 0, start: start, c1: c1, c2: c2, end: end
        )
        let b = CombatShotMotion.pointAlongCubicBezier(
            fraction: 1, start: start, c1: c1, c2: c2, end: end
        )
        #expect(abs(a.x - start.x) < 0.0001 && abs(a.y - start.y) < 0.0001)
        #expect(abs(b.x - end.x) < 0.0001 && abs(b.y - end.y) < 0.0001)
    }

    @Test func arcLengthIsLinearOnAStraightPath() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 0)
        let c1 = CGPoint(x: 33, y: 0)
        let c2 = CGPoint(x: 66, y: 0)
        let mid = CombatShotMotion.pointAlongCubicBezier(
            fraction: 0.5, start: start, c1: c1, c2: c2, end: end
        )
        #expect(abs(mid.x - 50) < 1)
        #expect(abs(mid.y) < 0.0001)
    }

    @Test func easedArcLengthStepsGetShorter() {
        let start = CGPoint(x: 0, y: 200)
        let end = CGPoint(x: 0, y: 0)
        let c1 = CGPoint(x: 0, y: 140)
        let c2 = CGPoint(x: 0, y: 60)
        var last = start
        var previousStep: CGFloat = .greatestFiniteMagnitude
        for i in 1...10 {
            let t = CGFloat(i) / 10
            let point = CombatShotMotion.pointAlongCubicBezier(
                fraction: CombatShotMotion.easeOut(t),
                start: start,
                c1: c1,
                c2: c2,
                end: end
            )
            let step = hypot(point.x - last.x, point.y - last.y)
            #expect(step < previousStep)
            previousStep = step
            last = point
        }
    }

    @Test func remainingArcLengthIsTheTailOfTheCurve() {
        #expect(CombatShotMotion.remainingArcLength(fraction: 0, total: 200) == 200)
        #expect(CombatShotMotion.remainingArcLength(fraction: 1, total: 200) == 0)
        #expect(abs(CombatShotMotion.remainingArcLength(fraction: 0.25, total: 200) - 150) < 0.0001)
    }

    @Test func straightPathArcLengthMatchesDistance() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 80, y: 60)
        let length = CombatShotMotion.cubicBezierArcLength(
            start: start,
            c1: CGPoint(x: 20, y: 15),
            c2: CGPoint(x: 60, y: 45),
            end: end
        )
        #expect(abs(length - 100) < 1)
    }

    @Test func projectileHitsPlayerOnlyWhenSpritesWouldOverlap() {
        let radii: CGFloat = 20 + 10
        let reach = radii * CombatShotMotion.hitDistanceScale
        #expect(abs(CombatShotMotion.hitDistanceScale - 0.60) < 0.0001)
        #expect(
            CombatShotMotion.projectileHitsPlayer(
                remainingArcLength: reach,
                projectileRadius: 20,
                playerRadius: 10
            )
        )
        #expect(
            !CombatShotMotion.projectileHitsPlayer(
                remainingArcLength: radii,
                projectileRadius: 20,
                playerRadius: 10
            )
        )
        #expect(
            !CombatShotMotion.projectileHitsPlayer(
                remainingArcLength: 200,
                projectileRadius: 60,
                playerRadius: 40
            )
        )
    }

    @Test func accelerateRemainingSegmentRestartsTheLeftoverArcAtDoubleSpeed() {
        let elapsed = 6.0
        let startedAt = 2.0
        let duration = 8.0
        let beforeT = CombatShotMotion.pathProgress(
            elapsed: elapsed, startedAt: startedAt, duration: duration
        )
        #expect(abs(beforeT - 0.5) < 0.0001)
        let beforeArc = CombatShotMotion.inboundArcFraction(progress: beforeT, arcStart: 0)

        let segment = CombatShotMotion.accelerateRemainingSegment(
            elapsed: elapsed,
            startedAt: startedAt,
            duration: duration,
            arcStart: 0,
            multiplier: 2
        )
        #expect(abs(segment.duration - 2) < 0.0001)
        #expect(abs(segment.startedAt - elapsed) < 0.0001)
        #expect(abs(segment.arcStart - beforeArc) < 0.0001)
        let afterT = CombatShotMotion.pathProgress(
            elapsed: elapsed, startedAt: segment.startedAt, duration: segment.duration
        )
        #expect(afterT == 0)
        let afterArc = CombatShotMotion.inboundArcFraction(
            progress: afterT, arcStart: segment.arcStart
        )
        #expect(abs(afterArc - beforeArc) < 0.0001)

        let later = elapsed + 1
        let rushed = CombatShotMotion.inboundArcFraction(
            progress: CombatShotMotion.pathProgress(
                elapsed: later, startedAt: segment.startedAt, duration: segment.duration
            ),
            arcStart: segment.arcStart
        )
        let unaccelerated = CombatShotMotion.inboundArcFraction(
            progress: CombatShotMotion.pathProgress(
                elapsed: later, startedAt: startedAt, duration: duration
            ),
            arcStart: 0
        )
        #expect(rushed > unaccelerated)
    }

    @Test func accelerateRemainingSegmentStacksOnASecondApply() {
        let elapsed = 6.0
        let first = CombatShotMotion.accelerateRemainingSegment(
            elapsed: elapsed,
            startedAt: 2,
            duration: 8,
            arcStart: 0,
            multiplier: 2
        )
        let second = CombatShotMotion.accelerateRemainingSegment(
            elapsed: elapsed,
            startedAt: first.startedAt,
            duration: first.duration,
            arcStart: first.arcStart,
            multiplier: 2
        )
        #expect(abs(first.duration - 2) < 0.0001)
        #expect(abs(second.duration - 1) < 0.0001)
        #expect(abs(second.arcStart - first.arcStart) < 0.0001)
        #expect(
            CombatShotMotion.pathProgress(
                elapsed: elapsed, startedAt: second.startedAt, duration: second.duration
            ) == 0
        )
    }

    @Test func accelerateRemainingSegmentSkipsFinishedAndNonSpeedingMultipliers() {
        let finished = CombatShotMotion.accelerateRemainingSegment(
            elapsed: 10,
            startedAt: 0,
            duration: 8,
            arcStart: 0.4,
            multiplier: 2
        )
        #expect(finished.startedAt == 0)
        #expect(finished.duration == 8)
        #expect(finished.arcStart == 0.4)

        let identity = CombatShotMotion.accelerateRemainingSegment(
            elapsed: 4,
            startedAt: 0,
            duration: 8,
            arcStart: 0,
            multiplier: 1
        )
        #expect(identity.startedAt == 0)
        #expect(identity.duration == 8)

        let slower = CombatShotMotion.accelerateRemainingSegment(
            elapsed: 4,
            startedAt: 0,
            duration: 8,
            arcStart: 0,
            multiplier: 0.5
        )
        #expect(slower.startedAt == 0)
        #expect(slower.duration == 8)
    }
}
