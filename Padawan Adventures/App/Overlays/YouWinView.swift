import SwiftUI

struct YouWinView: View {
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onFinished() }

            Text("You win!")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityIdentifier("youWin.title")
        }
        .accessibilityIdentifier("youWin.root")
    }
}
