import SwiftUI
import UIKit

struct MenuView: View {
    let session: AppSession
    let router: FlowRouter
    private let screenBackground: String?
    @State private var showContinue = false
    @State private var logoImage: UIImage?

    init(session: AppSession, router: FlowRouter) {
        self.session = session
        self.router = router
        self.screenBackground = (try? ScreenConfig.loadFromBundle(named: "menu"))?.background
    }

    var body: some View {
        AppScreen(
            backgroundNamed: screenBackground,
            backgroundLibrary: session.backgroundLibrary
        ) {
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
                                    router.navigate(to: .levelSelect)
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
        .playScreenMusic("menu")
        .task {
            await session.refreshContinueEligibility()
            showContinue = session.hasCompatibleSave
            await loadLogo()
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

    @MainActor
    private func loadLogo() async {
        if let existing = session.spriteLibrary.uiImage(id: "logo") {
            logoImage = existing
            return
        }
        guard let config = try? LoadingSpritesConfig.loadFromBundle() else { return }
        await session.spriteLibrary.ensureLoaded(config.logo.sprite, id: "logo")
        logoImage = session.spriteLibrary.uiImage(id: "logo")
    }
}
