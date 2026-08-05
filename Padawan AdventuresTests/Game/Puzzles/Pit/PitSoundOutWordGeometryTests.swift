import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct PitSoundOutWordGeometryTests {
    private let sceneSize = CGSize(width: 390, height: 844)
    private let padSize = CGSize(width: 120, height: 90)

    private func geometry(stepCount: Int) -> PitSoundOutWordGeometry {
        PitSoundOutWordGeometry(
            sceneSize: sceneSize,
            padSize: padSize,
            stepCount: stepCount
        )
    }

    @Test func stepColumnsLieBetweenPads() {
        for stepCount in 2...6 {
            let geo = geometry(stepCount: stepCount)
            for step in 0..<stepCount {
                let x = geo.stepColumnX(step)
                #expect(x > geo.leftPadRect.maxX)
                #expect(x < geo.rightPadRect.minX)
            }
        }
    }

    @Test func candidateCentersStayOnScreenBelowPrompt() {
        for count in 2...6 {
            let geo = geometry(stepCount: 3)
            let topLimit = geo.promptCenter.y - geo.promptMaxSide * 0.75
            for candidate in 0..<count {
                let center = geo.candidateCenter(step: 0, candidate: candidate, count: count)
                #expect(center.x >= 0)
                #expect(center.x <= sceneSize.width)
                #expect(center.y >= 0)
                #expect(center.y <= sceneSize.height)
                #expect(center.y <= topLimit + 0.001)
            }
        }
    }

    @Test func candidateFanIsShiftedDownFromPadMidline() {
        let geo = geometry(stepCount: 3)
        #expect(geo.candidateFanMidY == geo.leftPadRect.midY * 0.7)
        let center = geo.candidateCenter(step: 0, candidate: 1, count: 3)
        #expect(center.y == geo.candidateFanMidY)
    }

    @Test func candidateJitterRespectsAxisScales() {
        let geo = geometry(stepCount: 3)
        var rng = PitSeededGenerator(seed: 9)
        let limitX = geo.tileSide * PitSoundOutWordGeometry.candidateJitterXScale
        let limitY = geo.tileSide * PitSoundOutWordGeometry.candidateJitterYScale
        for _ in 0..<40 {
            let jitter = geo.randomCandidateJitter(using: &rng)
            #expect(abs(jitter.x) <= limitX + 0.000_1)
            #expect(abs(jitter.y) <= limitY + 0.000_1)
        }
    }

    @Test func candidateJittersNeverOverlap() {
        for count in 2...6 {
            let geo = geometry(stepCount: 4)
            for seed in UInt64(1)...UInt64(30) {
                var rng = PitSeededGenerator(seed: seed)
                let jitters = geo.candidateJitters(step: 1, count: count, using: &rng)
                #expect(jitters.count == count)
                let positions = (0..<count).map { index in
                    let center = geo.candidateCenter(step: 1, candidate: index, count: count)
                    let jitter = jitters[index]
                    return CGPoint(x: center.x + jitter.x, y: center.y + jitter.y)
                }
                for i in 0..<count {
                    for j in (i + 1)..<count {
                        #expect(!geo.candidatesOverlap(positions[i], positions[j]))
                    }
                }
            }
        }
    }

    @Test func nearestCandidatePicksExactCenterAndCloserMidpoint() {
        let geo = geometry(stepCount: 3)
        let count = 3
        for index in 0..<count {
            let center = geo.candidateCenter(step: 1, candidate: index, count: count)
            #expect(geo.nearestCandidate(to: center, step: 1, count: count) == index)
        }

        let a = geo.candidateCenter(step: 1, candidate: 0, count: count)
        let b = geo.candidateCenter(step: 1, candidate: 1, count: count)
        let midpoint = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
        let nudgedTowardA = CGPoint(
            x: midpoint.x + (a.x - midpoint.x) * 0.1,
            y: midpoint.y + (a.y - midpoint.y) * 0.1
        )
        #expect(geo.nearestCandidate(to: nudgedTowardA, step: 1, count: count) == 0)
    }
}
