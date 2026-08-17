import SwiftUI
import UIKit

/// Overlay shown after tapping a planet on the level-select screen.
struct LevelDetailOverlay: View {
    let levelName: String
    let nameStringID: String
    let mode: LevelDetailMode
    var startIcon: UIImage? = nil
    var secondaryIcon: UIImage? = nil
    let onStart: () -> Void
    var onStartOver: (() -> Void)? = nil
    let onDismiss: () -> Void

    private var startTitle: String {
        switch mode {
        case .firstStart, .continueAdventure:
            return Strings.text("level_detail_take_off")
        case .replay:
            return Strings.text("level_detail_try_again")
        }
    }

    private var secondaryTitle: String {
        switch mode {
        case .continueAdventure:
            return Strings.text("level_detail_start_over")
        case .firstStart:
            return Strings.text("level_detail_not_ready")
        case .replay:
            return Strings.text("level_detail_no_thanks")
        }
    }

    private var startAccessibilityID: String {
        switch mode {
        case .firstStart: return "levelSelect.detail.takeOff"
        case .continueAdventure: return "levelSelect.detail.continue"
        case .replay: return "levelSelect.detail.tryAgain"
        }
    }

    private var secondaryAccessibilityID: String {
        switch mode {
        case .firstStart: return "levelSelect.detail.notReady"
        case .continueAdventure: return "levelSelect.detail.startOver"
        case .replay: return "levelSelect.detail.noThanks"
        }
    }

    private var buttonWidth: CGFloat {
        AppLargeButton.consoleWidth(fittingTitles: [startTitle, secondaryTitle], includeIcon: true)
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

                    promptRow

                    AppLargeButton(
                        title: startTitle,
                        accessibilityID: startAccessibilityID,
                        style: .console,
                        icon: startIcon,
                        soundEvent: "takeoff",
                        action: onStart
                    )
                    .frame(width: buttonWidth)

                    AppLargeButton(
                        title: secondaryTitle,
                        accessibilityID: secondaryAccessibilityID,
                        style: .console,
                        icon: secondaryIcon,
                        action: secondaryAction
                    )
                    .frame(width: buttonWidth)
                }
            }
            .frame(maxWidth: AppChrome.maxContentWidth * 0.85)
        }
        .onChange(of: mode, initial: true) { _, newMode in
            if let speakID = newMode.promptSpeakID {
                Strings.speak(speakID)
            }
        }
    }

    @ViewBuilder
    private var promptRow: some View {
        switch mode {
        case .firstStart:
            EmptyView()
        case .continueAdventure:
            ModalCRTText(
                text: Strings.text(
                    "level_detail_continue_prompt",
                    ["planet": levelName]
                ),
                size: 20,
                weight: .semibold,
                accessibilityID: "levelSelect.detail.continuePrompt",
                speakID: "level_detail_continue_prompt"
            )
        case .replay(let highestStars):
            HStack(alignment: .center, spacing: 8) {
                ModalCRTText(
                    text: Strings.text("level_detail_replay_prompt"),
                    size: 20,
                    weight: .semibold
                )
                HStack(alignment: .center, spacing: 4) {
                    ScoreCoinIcon.Image(side: 20)
                        .shadow(
                            color: StarWarsConsolePalette.crtGlow.opacity(0.45),
                            radius: 2
                        )
                    ModalCRTText(
                        text: String(highestStars),
                        size: 20,
                        weight: .semibold,
                        accessibilityID: "levelSelect.detail.highestScoreValue"
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("levelSelect.detail.highestScore")
        }
    }

    private func secondaryAction() {
        switch mode {
        case .continueAdventure:
            onStartOver?()
        case .firstStart, .replay:
            onDismiss()
        }
    }
}
