import SwiftUI

/// Overlay shown after tapping a playable planet on the level-select screen.
struct LevelDetailOverlay: View {
    let levelName: String
    let hasBeenPlayed: Bool
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

                if hasBeenPlayed {
                    HStack(spacing: 8) {
                        Text("Your highest score: \(highestStars)")
                            .font(AppFont.swiftUI(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .appCopyShadow()
                        ScoreCoinIcon.Image(side: 20)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("levelSelect.detail.highestScore")

                    AppLargeButton(
                        title: "Try again?",
                        accessibilityID: "levelSelect.detail.tryAgain",
                        soundEvent: "takeoff",
                        action: onStart
                    )
                    .frame(maxWidth: 280)
                } else {
                    AppLargeButton(
                        title: "Take off!",
                        accessibilityID: "levelSelect.detail.takeOff",
                        soundEvent: "takeoff",
                        action: onStart
                    )
                    .frame(maxWidth: 280)
                }
            }
            .padding(28)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity)
        }
    }
}
