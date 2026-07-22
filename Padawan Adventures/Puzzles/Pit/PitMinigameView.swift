import SwiftUI

struct PitMinigameView: View {
    let onFinished: () -> Void

    var body: some View {
        OverlayPlaceholderButton(
            title: "PIT!",
            foreground: .white,
            background: Color(red: 0.55, green: 0.25, blue: 0.1),
            accessibilityID: "minigame.pit",
            action: onFinished
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
