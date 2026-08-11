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
            ModalCRTPanel {
                VStack(spacing: 12) {
                    ModalCRTText(
                        text: Strings.text("you_win"),
                        size: 44,
                        weight: .bold,
                        accessibilityID: "youWin.title"
                    )

                    if didBeatPreviousScore {
                        ModalCRTText(
                            text: Strings.text(
                                "you_win_high_score",
                                ["score": String(newScore)]
                            ),
                            size: 22,
                            weight: .semibold,
                            color: StarWarsConsolePalette.solvedGreen,
                            glow: StarWarsConsolePalette.solvedGlow,
                            accessibilityID: "youWin.highScore"
                        )
                    }
                }
            }
            .frame(maxWidth: AppChrome.maxContentWidth * 0.85)
        }
        .onAppear { Strings.speak("you_win") }
    }
}
