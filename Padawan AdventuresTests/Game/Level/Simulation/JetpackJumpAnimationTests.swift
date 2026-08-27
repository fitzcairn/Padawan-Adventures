import Testing
@testable import Padawan_Adventures

struct JetpackJumpAnimationTests {
    @Test func frameCountsMatchSpec() {
        #expect(JetpackJumpAnimation.takeoffFrames.count == 13)
        #expect(JetpackJumpAnimation.hoverFrames.count == 3)
        #expect(JetpackJumpAnimation.landFrames.count == 11)
        #expect(abs(JetpackJumpAnimation.landDuration - 11.0 / 15.0) < 0.000_1)
        #expect(
            abs(
                JetpackJumpAnimation.duration
                    - (13.0 + 3.0 + 11.0) / 15.0
            ) < 0.000_1
        )
    }

    @Test func phasesFollowTakeoffHoverLand() {
        let duration = JetpackJumpAnimation.duration
        #expect(JetpackJumpAnimation.phase(elapsed: 0, duration: duration) == .takeoff)
        #expect(
            JetpackJumpAnimation.phase(
                elapsed: JetpackJumpAnimation.takeoffDuration - 0.01,
                duration: duration
            ) == .takeoff
        )
        #expect(
            JetpackJumpAnimation.phase(
                elapsed: JetpackJumpAnimation.takeoffDuration,
                duration: duration
            ) == .hover
        )
        #expect(
            JetpackJumpAnimation.phase(
                elapsed: duration - JetpackJumpAnimation.landDuration,
                duration: duration
            ) == .land
        )
        #expect(JetpackJumpAnimation.phase(elapsed: duration, duration: duration) == .land)
    }

    @Test func drawsInFrontOfGateAfterTakeoff() {
        let duration = JetpackJumpAnimation.duration
        #expect(
            JetpackJumpAnimation.drawsInFrontOfGate(elapsed: 0, duration: duration) == false
        )
        #expect(
            JetpackJumpAnimation.drawsInFrontOfGate(
                elapsed: JetpackJumpAnimation.takeoffDuration - 0.01,
                duration: duration
            ) == false
        )
        #expect(
            JetpackJumpAnimation.drawsInFrontOfGate(
                elapsed: JetpackJumpAnimation.takeoffDuration,
                duration: duration
            )
        )
        #expect(
            JetpackJumpAnimation.drawsInFrontOfGate(elapsed: duration, duration: duration)
        )
    }

    @Test func crossfadeIsFourFramesAtClipRate() {
        #expect(JetpackJumpAnimation.crossfadeFrames == 4)
        #expect(
            abs(JetpackJumpAnimation.crossfadeDuration - 4.0 / 15.0) < 0.000_1
        )
        #expect(JetpackJumpAnimation.crossfadeDuration < JetpackJumpAnimation.takeoffDuration)
        #expect(JetpackJumpAnimation.crossfadeDuration < JetpackJumpAnimation.landDuration)
    }

    @Test func clipNameCoversEveryFacing() {
        #expect(JetpackJumpAnimation.clipName(for: .up) == "jetpack_northeast")
        #expect(JetpackJumpAnimation.clipName(for: .northeast) == "jetpack_northeast")
        #expect(JetpackJumpAnimation.clipName(for: .northwest) == "jetpack_northwest")
        #expect(JetpackJumpAnimation.clipName(for: .left) == "jetpack_northwest")
        #expect(JetpackJumpAnimation.clipName(for: .right) == "jetpack_southeast")
        #expect(JetpackJumpAnimation.clipName(for: .southeast) == "jetpack_southeast")
        #expect(JetpackJumpAnimation.clipName(for: .down) == "jetpack_southeast")
        #expect(JetpackJumpAnimation.clipName(for: .southwest) == "jetpack_southwest")
    }
}
