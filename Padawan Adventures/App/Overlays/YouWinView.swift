import SwiftUI

struct YouWinView: View {
    var didBeatPreviousScore: Bool = false
    var newScore: Int = 0
    let onFinished: () -> Void

    var body: some View {
        DismissibleOverlay(
            accessibilityRootID: "youWin.root",
            onFinished: onFinished
        ) {
            VStack(spacing: 12) {
                Text(Strings.text("you_win"))
                    .font(AppFont.swiftUI(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .appCopyShadow()
                    .accessibilityIdentifier("youWin.title")

                if didBeatPreviousScore {
                    Text(Strings.text("you_win_high_score", ["score": String(newScore)]))
                        .font(AppFont.swiftUI(size: 22, weight: .semibold))
                        .foregroundStyle(.orange)
                        .appCopyShadow()
                        .accessibilityIdentifier("youWin.highScore")
                }
            }
        }
        .onAppear { Strings.speak("you_win") }
    }
}
