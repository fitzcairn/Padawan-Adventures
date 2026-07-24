import SwiftUI

struct MenuView: View {
    let session: AppSession
    let router: FlowRouter
    @State private var showContinue = false

    var body: some View {
        AppScreen {
            VStack(spacing: 0) {
                AppTitleText(
                    text: session.currentPlayerName.map { "Welcome, \($0)" } ?? "Welcome",
                    size: 24,
                    weight: .semibold
                )
                .accessibilityIdentifier("menu.welcome")

                Spacer()

                VStack(spacing: 16) {
                    if showContinue {
                        AppLargeButton(title: "CONTINUE", accessibilityID: "menu.continue") {
                            router.navigate(to: .preparing(.continueSave))
                        }
                    }

                    AppLargeButton(title: "NEW GAME", accessibilityID: "menu.newGame") {
                        Task {
                            await session.beginNewGame()
                            router.navigate(to: .levelSelect)
                        }
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

                Spacer()

                AppTitleText(
                    text: AppChrome.versionBuildString,
                    size: 13,
                    weight: .regular,
                    color: AppChrome.secondaryTextColor
                )
                .accessibilityIdentifier("menu.version")
            }
        }
        .playScreenMusic("menu")
        .task {
            await session.refreshContinueEligibility()
            showContinue = session.hasCompatibleSave
        }
    }
}
