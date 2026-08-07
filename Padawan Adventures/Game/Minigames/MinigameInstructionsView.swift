import SwiftUI

/// Placeholder first-encounter instructions screen for a minigame variation.
struct MinigameInstructionsView: View {
    /// Minigame `kind` raw value (e.g. `"ending-sound-pit"`).
    let instructionsKey: String
    let onContinue: () -> Void

    private var bodyStringID: String {
        Self.bodyStringID(forKindRawValue: instructionsKey)
    }

    var body: some View {
        ZStack {
            OverlayChrome.backgroundColor.ignoresSafeArea()

            Text(Strings.text(bodyStringID))
                .font(AppFont.swiftUI(size: 32, weight: .bold))
                .foregroundStyle(AppChrome.primaryTextColor)
                .multilineTextAlignment(.center)
                .appCopyShadow()
                .padding(.horizontal, 32)
                .accessibilityIdentifier("minigame.instructions.body")

            VStack {
                Spacer()
                Text(Strings.text("minigame_instructions_continue"))
                    .font(AppFont.swiftUI(size: 22, weight: .semibold))
                    .foregroundStyle(AppChrome.primaryTextColor)
                    .appCopyShadow()
                    .padding(.bottom, 32)
                    .accessibilityIdentifier("minigame.instructions.continue")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onContinue() }
        .onAppear { Strings.speak(bodyStringID) }
        .accessibilityIdentifier("minigame.instructions.root")
    }

    /// Maps a minigame kind raw value to its per-variation instructions string id.
    static func bodyStringID(forKindRawValue key: String) -> String {
        "minigame_instructions_" + key.replacingOccurrences(of: "-", with: "_")
    }
}

/// Shows `MinigameInstructionsView` once before building the minigame content.
///
/// `content` (and therefore the SpriteKit scene, its timers and its audio) is not
/// constructed until the player taps through.
struct MinigameInstructionsGate<Content: View>: View {
    private let needsInstructions: Bool
    private let instructionsKey: String
    private let onAcknowledged: () -> Void
    private let content: () -> Content

    @State private var acknowledged = false

    init(
        needsInstructions: Bool,
        instructionsKey: String,
        onAcknowledged: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.needsInstructions = needsInstructions
        self.instructionsKey = instructionsKey
        self.onAcknowledged = onAcknowledged
        self.content = content
    }

    var body: some View {
        if needsInstructions, !acknowledged {
            MinigameInstructionsView(instructionsKey: instructionsKey) {
                acknowledged = true
                onAcknowledged()
            }
        } else {
            content()
        }
    }
}
