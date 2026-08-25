import SwiftUI
import UIKit

/// Confirmation shown when New Game would wipe in-progress progress.
struct NewGameConfirmOverlay: View {
    var confirmIcon: UIImage? = nil
    var cancelIcon: UIImage? = nil
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var confirmTitle: String { Strings.text("level_detail_take_off") }
    private var cancelTitle: String { Strings.text("button_cancel") }

    private var buttonWidth: CGFloat {
        AppLargeButton.consoleWidth(fittingTitles: [confirmTitle, cancelTitle], includeIcon: true)
    }

    var body: some View {
        ModalOverlayShell(
            accessibilityRootID: "menu.newGameConfirm.root",
            onBackgroundTap: onCancel
        ) {
            ModalCRTPanel {
                VStack(spacing: 20) {
                    ModalCRTText(
                        text: Strings.text("menu_new_game_confirm"),
                        size: 32,
                        weight: .bold,
                        accessibilityID: "menu.newGameConfirm.message"
                    )

                    AppLargeButton(
                        title: confirmTitle,
                        accessibilityID: "menu.newGameConfirm.letsGo",
                        style: .console,
                        icon: confirmIcon,
                        action: onConfirm
                    )
                    .frame(width: buttonWidth)

                    AppLargeButton(
                        title: cancelTitle,
                        accessibilityID: "menu.newGameConfirm.cancel",
                        style: .console,
                        icon: cancelIcon,
                        action: onCancel
                    )
                    .frame(width: buttonWidth)
                }
            }
            .frame(maxWidth: AppChrome.maxContentWidth * 0.85)
        }
    }
}
