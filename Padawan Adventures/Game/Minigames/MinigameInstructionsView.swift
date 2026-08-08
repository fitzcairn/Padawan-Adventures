import SwiftUI

/// First-encounter instructions screen for a minigame variation.
///
/// Hosts a scripted demo behind a tap-catcher so the player cannot interact with
/// the scene; tapping anywhere dismisses into the real minigame.
struct MinigameInstructionsView<Demo: View>: View {
    /// Minigame `kind` raw value (e.g. `"ending-sound-pit"`).
    let instructionsKey: String
    let onContinue: () -> Void
    @ViewBuilder var demo: () -> Demo

    private var bodyStringID: String {
        Self.bodyStringID(forKindRawValue: instructionsKey)
    }

    var body: some View {
        ZStack {
            OverlayChrome.backgroundColor.ignoresSafeArea()

            demo()

            VStack {
                Spacer()
                Text(Strings.text("minigame_instructions_continue"))
                    .font(AppFont.swiftUI(size: 22, weight: .semibold))
                    .foregroundStyle(AppChrome.primaryTextColor)
                    .appCopyShadow()
                    .padding(.bottom, 32)
                    .accessibilityIdentifier("minigame.instructions.continue")
            }

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
        .accessibilityIdentifier("minigame.instructions.root")
    }

    /// Maps a minigame kind raw value to its per-variation instructions string id.
    static func bodyStringID(forKindRawValue key: String) -> String {
        "minigame_instructions_" + key.replacingOccurrences(of: "-", with: "_")
    }

    /// Seconds to wait after speaking the voice-over before the demo starts driving
    /// the scene (so game audio does not talk over the instructions).
    static func leadInSeconds(forKindRawValue key: String) -> TimeInterval {
        let id = bodyStringID(forKindRawValue: key)
        let trackID = Strings.catalog.entry(id)?.sfx
        return SoundEffectsController.shared.cueDuration(of: trackID) + 0.3
    }
}

/// Shows `MinigameInstructionsView` once before building the minigame content.
///
/// `content` (and therefore the SpriteKit scene, its timers and its audio) is not
/// constructed until the player taps through. The demo scene is built immediately
/// when instructions are shown.
struct MinigameInstructionsGate<Demo: View, Content: View>: View {
    private let needsInstructions: Bool
    private let instructionsKey: String
    private let onAcknowledged: () -> Void
    private let demo: () -> Demo
    private let content: () -> Content

    @State private var acknowledged = false

    init(
        needsInstructions: Bool,
        instructionsKey: String,
        onAcknowledged: @escaping () -> Void,
        @ViewBuilder demo: @escaping () -> Demo,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.needsInstructions = needsInstructions
        self.instructionsKey = instructionsKey
        self.onAcknowledged = onAcknowledged
        self.demo = demo
        self.content = content
    }

    var body: some View {
        if needsInstructions, !acknowledged {
            MinigameInstructionsView(instructionsKey: instructionsKey) {
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
