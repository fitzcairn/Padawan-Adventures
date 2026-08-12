import Foundation

/// Voice-over timing for the first-encounter minigame tutorial screen.
enum MinigameTutorialVoiceOver {
    /// Spoken "tap to continue" hint, played once each time the demo animation ends.
    static let continueStringID = "minigame_tutorial_continue"

    /// Used when a tutorial line has no clip in the bundle, so the demo still holds
    /// long enough to read as a deliberate pause.
    static let fallbackSeconds: TimeInterval = 3

    /// Clip length of the entry's voice-over, or nil when it cannot be resolved.
    static func seconds(forStringID id: String) -> TimeInterval? {
        guard let sfx = Strings.catalog.entry(id)?.sfx else { return nil }
        return SoundEffectsController.shared.duration(of: sfx)
    }

    /// Speaks the "tap to continue" line and waits for it to finish so the next demo
    /// cycle's audio does not start underneath it.
    static func playContinueCue() async {
        Strings.speak(continueStringID)
        guard let seconds = seconds(forStringID: continueStringID), seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
