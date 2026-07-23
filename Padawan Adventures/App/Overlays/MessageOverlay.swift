import SwiftUI

/// Shared fullscreen message overlay for flow screens (uses `DismissibleOverlay`).
struct MessageOverlay: View {
    let title: String
    var accessibilityRootID: String = "messageOverlay.root"
    var accessibilityTitleID: String = "messageOverlay.title"
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(
            accessibilityRootID: accessibilityRootID,
            onFinished: onFinished
        ) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .accessibilityIdentifier(accessibilityTitleID)
        }
    }
}
