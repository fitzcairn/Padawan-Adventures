import SwiftUI

/// Overlay shown after tapping a previously played planet on the level-select screen.
struct LevelDetailOverlay: View {
    let levelName: String
    let highestStars: Int
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: "levelSelect.detail.root",
            onBackgroundTap: onDismiss
        ) {
            VStack(spacing: 20) {
                Text(levelName)
                    .font(AppFont.swiftUI(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .appCopyShadow()
                    .accessibilityIdentifier("levelSelect.detail.title")

                HStack(spacing: 8) {
                    Text(
                        Strings.text(
                            "level_detail_highest_score",
                            ["stars": String(highestStars)]
                        )
                    )
                        .font(AppFont.swiftUI(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .appCopyShadow()
                    ScoreCoinIcon.Image(side: 20)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("levelSelect.detail.highestScore")

                AppLargeButton(
                    title: Strings.text("level_detail_try_again"),
                    accessibilityID: "levelSelect.detail.tryAgain",
                    soundEvent: "takeoff",
                    action: onStart
                )
                .frame(maxWidth: 280)

                AppLargeButton(
                    title: Strings.text("level_detail_no_thanks"),
                    accessibilityID: "levelSelect.detail.noThanks",
                    action: onDismiss
                )
                .frame(maxWidth: 280)
            }
            .padding(28)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity)
        }
    }
}
