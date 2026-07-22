import SwiftUI

struct DefeatView: View {
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            OverlayPlaceholderButton(
                title: "Defeated",
                foreground: .white,
                background: Color(white: 0.22),
                accessibilityID: "defeat.button",
                action: onFinished
            )
        }
        .accessibilityIdentifier("defeat.root")
    }
}
