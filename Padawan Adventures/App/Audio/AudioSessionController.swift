import AVFoundation
import Foundation

/// Owns the process audio session shared by bundle music, SFX, and cutscene video.
///
/// The game takes sole use of the output while it is in the foreground, so whatever the
/// device was streaming (Music, a podcast, Spotify) is interrupted instead of mixing into
/// the phonics cues. `soloAmbient` keeps the ring-switch behaviour of the earlier ambient
/// session, and releasing with `notifyOthersOnDeactivation` is what lets the interrupted app
/// resume once the game is backgrounded or terminated.
enum AudioSessionController {
    private static var isActive = false
    /// Set while the game has stepped aside, so a stray cue cannot grab the output back.
    private static var hasYielded = false

    /// Test seam: whether the game currently holds the session.
    static var isActiveForTesting: Bool { isActive }

    /// Claims the output for game audio, interrupting any other app that is playing.
    static func claimOutput() {
        hasYielded = false
        guard !isActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.soloAmbient, mode: .default, options: [])
            try session.setActive(true)
            isActive = true
            GameLogger.mark(.audio, "audio session claimed output")
        } catch {
            GameLogger.fault(.audio, "audio session activation failed: \(error)")
        }
    }

    /// Claim performed lazily by players, skipped while the game is in the background.
    static func claimOutputIfNeeded() {
        guard !hasYielded else { return }
        claimOutput()
    }

    /// Foreground entry point: game audio resumes and takes the output back.
    @MainActor
    static func claimForForeground() {
        claimOutput()
        BackgroundMusicController.shared.resumeFromBackground()
    }

    /// Background / termination entry point. Game audio has to stop before the session can
    /// be released, and loops do not survive suspension anyway, so they are dropped here.
    @MainActor
    static func releaseForBackground() {
        BackgroundMusicController.shared.pauseForBackground()
        SoundEffectsController.shared.stopAllLoops()
        yieldOutput()
    }

    /// Releases the output and tells the interrupted app that it may resume. Callers should
    /// pause game audio first: an active player makes deactivation fail.
    static func yieldOutput() {
        hasYielded = true
        guard isActive else { return }
        do {
            try AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            GameLogger.mark(.audio, "audio session released output")
        } catch {
            // The system deactivates the session anyway once the app suspends.
            GameLogger.mark(.audio, "audio session release deferred: \(error)")
        }
    }
}
