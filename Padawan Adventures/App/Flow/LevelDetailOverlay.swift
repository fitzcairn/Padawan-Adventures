import SwiftUI
import UIKit

/// Overlay shown after tapping a planet on the level-select screen.
struct LevelDetailOverlay: View {
    let levelName: String
    let nameStringID: String
    /// `nil` for a first start — hides the highest-score row.
    let highestStars: Int?
    var startIcon: UIImage? = nil
    var dismissIcon: UIImage? = nil
    let onStart: () -> Void
    let onDismiss: () -> Void

    private var isReplay: Bool { highestStars != nil }

    private var startTitle: String {
        Strings.text(isReplay ? "level_detail_try_again" : "level_detail_take_off")
    }

    private var dismissTitle: String {
        Strings.text(isReplay ? "level_detail_no_thanks" : "level_detail_not_ready")
    }

    private var buttonWidth: CGFloat {
        AppLargeButton.consoleWidth(fittingTitles: [startTitle, dismissTitle], includeIcon: true)
    }

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: "levelSelect.detail.root",
            onBackgroundTap: onDismiss
        ) {
            ModalCRTPanel {
                VStack(spacing: 20) {
                    ModalCRTText(
                        text: levelName,
                        size: 32,
                        weight: .bold,
                        accessibilityID: "levelSelect.detail.title",
                        speakID: nameStringID
                    )

                    if let highestStars {
                        HStack(spacing: 8) {
                            ModalCRTText(
                                text: Strings.text(
                                    "level_detail_highest_score",
                                    ["stars": String(highestStars)]
                                ),
                                size: 20,
                                weight: .semibold
                            )
                            ScoreCoinIcon.Image(side: 20)
                                .shadow(
                                    color: StarWarsConsolePalette.crtGlow.opacity(0.45),
                                    radius: 2
                                )
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("levelSelect.detail.highestScore")
                    }

                    AppLargeButton(
                        title: startTitle,
                        accessibilityID: isReplay
                            ? "levelSelect.detail.tryAgain"
                            : "levelSelect.detail.takeOff",
                        style: .console,
                        icon: startIcon,
                        soundEvent: "takeoff",
                        action: onStart
                    )
                    .frame(width: buttonWidth)

                    AppLargeButton(
                        title: dismissTitle,
                        accessibilityID: isReplay
                            ? "levelSelect.detail.noThanks"
                            : "levelSelect.detail.notReady",
                        style: .console,
                        icon: dismissIcon,
                        action: onDismiss
                    )
                    .frame(width: buttonWidth)
                }
            }
            .frame(maxWidth: AppChrome.maxContentWidth * 0.85)
        }
    }
}
