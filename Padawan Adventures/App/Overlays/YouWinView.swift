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

                    HStack(spacing: 8) {
                        ModalCRTText(
                            text: String(newScore),
                            size: 28,
                            weight: .semibold,
                            accessibilityID: "youWin.score"
                        )
                        ScoreCoinIcon.Image(side: 28)
                            .shadow(
                                color: StarWarsConsolePalette.crtGlow.opacity(0.45),
                                radius: 2
                            )
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("youWin.coins")

                    if didBeatPreviousScore {
                        ModalCRTText(
                            text: Strings.text("you_win_high_score"),
                            size: 22,
                            weight: .semibold,
                            color: StarWarsConsolePalette.solvedGreen,
                            glow: StarWarsConsolePalette.solvedGlow,
                            accessibilityID: "youWin.highScore",
                            speakID: "you_win_high_score"
                        )
                    }
                }
            }
            .frame(maxWidth: AppChrome.maxContentWidth * 0.85)
        }
        .onAppear { Strings.speak("you_win") }
    }
}
