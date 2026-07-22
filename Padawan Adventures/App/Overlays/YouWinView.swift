import SwiftUI

struct YouWinView: View {
    var didBeatPreviousScore: Bool = false
    var newScore: Int = 0
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onFinished() }

            VStack(spacing: 12) {
                Text("You win!")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("youWin.title")

                if didBeatPreviousScore {
                    Text("New high score: \(newScore)!")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("youWin.highScore")
                }
            }
        }
        .accessibilityIdentifier("youWin.root")
    }
}
