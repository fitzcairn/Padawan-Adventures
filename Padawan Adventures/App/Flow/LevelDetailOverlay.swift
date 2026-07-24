import SwiftUI

/// Overlay shown after tapping a playable planet on the level-select screen.
struct LevelDetailOverlay: View {
    let levelName: String
    let hasBeenPlayed: Bool
    let highestStars: Int
    let onStart: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 20) {
                Text(levelName)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("levelSelect.detail.title")

                if hasBeenPlayed {
                    HStack(spacing: 8) {
                        Text("Your highest score: \(highestStars)")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("levelSelect.detail.highestScore")

                    AppLargeButton(
                        title: "Try again?",
                        accessibilityID: "levelSelect.detail.tryAgain",
                        action: onStart
                    )
                    .frame(maxWidth: 280)
                } else {
                    AppLargeButton(
                        title: "Take off!",
                        accessibilityID: "levelSelect.detail.takeOff",
                        action: onStart
                    )
                    .frame(maxWidth: 280)
                }
            }
            .padding(28)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity)
            .appScreenContentPadding()
        }
        .accessibilityIdentifier("levelSelect.detail.root")
    }
}
