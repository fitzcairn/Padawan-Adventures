import SwiftUI

struct DefeatView: View {
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(
            accessibilityRootID: "defeat.root",
            onFinished: onFinished
        ) {
            Text(Strings.text("defeated"))
                .font(AppFont.swiftUI(size: 22, weight: .semibold))
                .foregroundStyle(AppChrome.buttonForegroundColor)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .appButtonChrome(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("defeat.button")
        }
        .onAppear { Strings.speak("defeated") }
    }
}
