import SwiftUI

/// First-encounter tutorial screen for a minigame variation.
///
/// Hosts a scripted demo behind a tap-catcher so the player cannot interact with
/// the scene; tapping anywhere dismisses into the real minigame.
struct MinigameTutorialView<Demo: View>: View {
    /// Minigame `kind` raw value (e.g. `"ending-sound-pit"`).
    let tutorialKey: String
    let onContinue: () -> Void
    @ViewBuilder var demo: () -> Demo

    private var bodyStringID: String {
        Self.bodyStringID(forKindRawValue: tutorialKey)
    }

    var body: some View {
        ZStack {
            OverlayChrome.backgroundColor.ignoresSafeArea()

            demo()

            VStack {
                Spacer()
                Text(Strings.text("minigame_tutorial_continue"))
                    .font(TutorialHintStyle.font)
                    .foregroundStyle(TutorialHintStyle.color)
                    .appCopyShadow()
                    .accessibilityIdentifier("minigame.tutorial.continue")
            }
            .appScreenContentPadding()

            // Swallows real touches so the player cannot play the demo scene.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    SoundEffectsController.shared.fadeOutAndStopAll()
                    onContinue()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Strings.speak(bodyStringID) }
        .accessibilityIdentifier("minigame.tutorial.root")
    }

    /// Maps a minigame kind raw value to its per-variation tutorial string id.
    static func bodyStringID(forKindRawValue key: String) -> String {
        "minigame_tutorial_" + key.replacingOccurrences(of: "-", with: "_")
    }

    /// Seconds to wait after the demo pointer is on screen before gestures start —
    /// the whole tutorial voice-over (spoken on appear) plays over a frozen arena.
    static func leadInSeconds(forKindRawValue key: String) -> TimeInterval {
        MinigameTutorialVoiceOver.seconds(forStringID: bodyStringID(forKindRawValue: key))
            ?? MinigameTutorialVoiceOver.fallbackSeconds
    }
}

/// Shows `MinigameTutorialView` once before building the minigame content.
///
/// `content` (and therefore the SpriteKit scene, its timers and its audio) is not
/// constructed until the player taps through. The demo scene is built immediately
/// when the tutorial is shown.
///
/// `needsTutorial` is re-checked on every body evaluation (not a captured Bool) so a
/// SwiftUI identity reset after acknowledge cannot replay a tutorial already marked
/// seen on the session.
struct MinigameTutorialGate<Demo: View, Content: View>: View {
    private let needsTutorial: () -> Bool
    private let tutorialKey: String
    private let onAcknowledged: () -> Void
    private let demo: () -> Demo
    private let content: () -> Content

    @State private var acknowledged = false

    init(
        needsTutorial: @escaping () -> Bool,
        tutorialKey: String,
        onAcknowledged: @escaping () -> Void,
        @ViewBuilder demo: @escaping () -> Demo,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.needsTutorial = needsTutorial
        self.tutorialKey = tutorialKey
        self.onAcknowledged = onAcknowledged
        self.demo = demo
        self.content = content
    }

    var body: some View {
        if needsTutorial(), !acknowledged {
            MinigameTutorialView(tutorialKey: tutorialKey) {
                acknowledged = true
                onAcknowledged()
            } demo: {
                demo()
            }
        } else {
            content()
        }
    }
}
