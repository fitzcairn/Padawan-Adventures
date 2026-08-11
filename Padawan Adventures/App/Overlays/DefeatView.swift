import SwiftUI

struct DefeatView: View {
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(
            accessibilityRootID: "defeat.root",
            onFinished: onFinished
        ) {
            ModalCRTPanel {
                ModalCRTText(
                    text: Strings.text("defeated"),
                    size: 32,
                    weight: .bold,
                    accessibilityID: "defeat.button"
                )
            }
            .frame(maxWidth: AppChrome.maxContentWidth * 0.85)
        }
        .onAppear { Strings.speak("defeated") }
    }
}
