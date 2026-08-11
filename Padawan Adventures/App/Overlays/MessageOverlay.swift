import SwiftUI

/// Shared fullscreen message overlay for flow screens (uses `DismissibleOverlay`).
struct MessageOverlay: View {
    let title: String
    var accessibilityRootID: String = "messageOverlay.root"
    var accessibilityTitleID: String = "messageOverlay.title"
    var speakStringID: String? = nil
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(
            accessibilityRootID: accessibilityRootID,
            onFinished: onFinished
        ) {
            ModalCRTPanel {
                ModalCRTText(
                    text: title,
                    size: 32,
                    weight: .bold,
                    accessibilityID: accessibilityTitleID,
                    speakID: speakStringID
                )
            }
            .frame(maxWidth: AppChrome.maxContentWidth * 0.85)
        }
        .onAppear {
            if let speakStringID {
                Strings.speak(speakStringID)
            }
        }
    }
}
