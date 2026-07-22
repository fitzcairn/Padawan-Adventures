import SwiftUI

struct GateMinigameView: View {
    let onFinished: () -> Void

    var body: some View {
        OverlayPlaceholderButton(
            title: "GATE ENCOUNTERED!!",
            foreground: Color(white: 0.1),
            background: Color(red: 0.55, green: 0.9, blue: 0.55),
            accessibilityID: "minigame.gate",
            action: onFinished
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
