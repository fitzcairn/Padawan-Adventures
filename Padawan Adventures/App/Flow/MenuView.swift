import SwiftUI
import UIKit

struct MenuView: View {
    let session: AppSession
    let router: FlowRouter
    private let screenBackground: String?
    @State private var showContinue = false
    @State private var logoImage: UIImage?
    @State private var isContentReady = false

    init(session: AppSession, router: FlowRouter) {
        self.session = session
        self.router = router
        self.screenBackground = (try? ScreenConfig.loadFromBundle(named: "menu"))?.background
        // Logo is warmed during the loading screen; paint it on the first ready frame.
        _logoImage = State(initialValue: session.spriteLibrary.uiImage(id: "logo"))
    }

    var body: some View {
        AppScreen(
            backgroundNamed: screenBackground,
            backgroundLibrary: session.backgroundLibrary
        ) {
            if isContentReady {
                menuContent
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("menu.loading")
            }
        }
        .playScreenMusic("menu")
        .task {
            // Assets are already warm from bootstrap; only resolve continue eligibility.
            await session.refreshContinueEligibility()
            logoImage = session.spriteLibrary.uiImage(id: "logo")
            showContinue = session.hasCompatibleSave
            isContentReady = true
        }
    }

    private var menuContent: some View {
        HStack(spacing: 32) {
            logoColumn

            ZStack(alignment: .bottom) {
                VStack(spacing: 24) {
                    AppTitleText(
                        text: session.currentPlayerName.map { "Welcome, \($0)" } ?? "Welcome",
                        size: 24,
                        weight: .semibold
                    )
                    .accessibilityIdentifier("menu.welcome")

                    VStack(spacing: 16) {
                        if showContinue {
                            AppLargeButton(title: "CONTINUE", accessibilityID: "menu.continue") {
                                router.navigate(to: .preparing(.continueSave))
                            }
                        }

                        AppLargeButton(title: "NEW GAME", accessibilityID: "menu.newGame") {
                            Task {
                                await session.beginNewGame()
                                router.navigate(to: .cutscene)
                            }
                        }

                        AppLargeButton(title: "SETTINGS", accessibilityID: "menu.settings") {
                            router.navigate(to: .settings)
                        }

                        AppLargeButton(title: "QUIT", accessibilityID: "menu.quit") {
                            exit(0)
                        }
                    }
                    .frame(maxWidth: AppChrome.maxContentWidth * 0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                AppTitleText(
                    text: AppChrome.versionBuildString,
                    size: 13,
                    weight: .regular,
                    color: AppChrome.secondaryTextColor
                )
                .accessibilityIdentifier("menu.version")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var logoColumn: some View {
        Group {
            if let logoImage {
                Image(uiImage: logoImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityIdentifier("menu.logo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
