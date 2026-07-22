import SwiftUI

struct OverlayPlaceholderButton: View {
    let title: String
    let foreground: Color
    let background: Color
    let accessibilityID: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(background, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}
