import AVFoundation
import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
struct AudioSessionControllerTests {
    /// Claiming must land on a non-mixing category, otherwise another app's stream
    /// would keep playing underneath the phonics cues.
    @Test func claimTakesSoleUseOfTheOutput() {
        AudioSessionController.claimOutput()
        #expect(AVAudioSession.sharedInstance().category == .soloAmbient)
        #expect(!AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers))
    }

    /// After yielding, playback started by a stray cue must not reactivate the session:
    /// that is what would cut off the other app's freshly resumed stream.
    @Test func yieldedSessionIsNotReclaimedLazily() {
        AudioSessionController.claimOutput()
        AudioSessionController.yieldOutput()
        AudioSessionController.claimOutputIfNeeded()
        #expect(!AudioSessionController.isActiveForTesting)

        // Leave the shared session as the app expects it for the rest of the suite.
        AudioSessionController.claimOutput()
        #expect(AudioSessionController.isActiveForTesting)
    }
}
