import SwiftUI

struct DefeatView: View {
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(
            accessibilityRootID: "defeat.root",
            onFinished: onFinished,
            background: { Color.black }
        ) {
            Text("Defeated")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("defeat.button")
        }
    }
}
