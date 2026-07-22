import SwiftUI

struct EnemyMinigameView: View {
    let onFinished: () -> Void

    var body: some View {
        OverlayPlaceholderButton(
            title: "Enemy fight!",
            foreground: .white,
            background: Color(red: 0.75, green: 0.15, blue: 0.15),
            accessibilityID: "minigame.enemy",
            action: onFinished
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
