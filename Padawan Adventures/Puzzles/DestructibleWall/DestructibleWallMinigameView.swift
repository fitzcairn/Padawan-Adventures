import SwiftUI

struct DestructibleWallMinigameView: View {
    let onFinished: () -> Void

    var body: some View {
        OverlayPlaceholderButton(
            title: "BOOM!",
            foreground: Color(white: 0.15),
            background: Color(red: 1.0, green: 0.92, blue: 0.45),
            accessibilityID: "minigame.boom",
            action: onFinished
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
