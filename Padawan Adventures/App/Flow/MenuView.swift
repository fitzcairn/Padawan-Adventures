import SwiftUI

struct MenuView: View {
    let session: AppSession
    let router: FlowRouter
    @State private var showContinue = false

    var body: some View {
        VStack(spacing: 0) {
            AppTitleText(
                text: session.currentPlayerName.map { "Welcome, \($0)" } ?? "Welcome",
                size: 24,
                weight: .semibold
            )
            .padding(.top, 24)
            .padding(.horizontal)
            .accessibilityIdentifier("menu.welcome")

            Spacer()

            VStack(spacing: 16) {
                if showContinue {
                    AppLargeButton(title: "CONTINUE", accessibilityID: "menu.continue") {
                        router.navigate(to: .preparing(.continueSave))
                    }
                }

                AppLargeButton(title: "NEW GAME", accessibilityID: "menu.newGame") {
                    router.navigate(to: .levelSelect)
                }

                AppLargeButton(title: "LEADERBOARD", accessibilityID: "menu.leaderboard") {
                    // Intentionally no-op for now.
                }

                AppLargeButton(title: "SETTINGS", accessibilityID: "menu.settings") {
                    router.navigate(to: .settings)
                }

                AppLargeButton(title: "QUIT", accessibilityID: "menu.quit") {
                    exit(0)
                }
            }
            .appReadableWidth()
            .padding(.horizontal)

            Spacer()

            AppTitleText(
                text: AppChrome.versionBuildString,
                size: 13,
                weight: .regular,
                color: AppChrome.secondaryTextColor
            )
            .padding(.bottom, 12)
            .accessibilityIdentifier("menu.version")
        }
        .appScreenBackground()
        .playScreenMusic("menu")
        .task {
            await session.refreshContinueEligibility()
            showContinue = session.hasCompatibleSave
        }
    }
}
