import SwiftUI
import UIKit

struct MenuView: View {
    let session: AppSession
    let router: FlowRouter
    private let screenBackground: String?
    @State private var showContinue = false
    @State private var logoImage: UIImage?
    @State private var menuIcons: [UIImage] = []
    @State private var isContentReady = false

    init(session: AppSession, router: FlowRouter) {
        self.session = session
        self.router = router
        self.screenBackground = (try? ScreenConfig.loadFromBundle(named: "menu"))?.background
        // Logo / menu icons are warmed during the loading screen; paint on the first ready frame.
        _logoImage = State(initialValue: session.spriteLibrary.uiImage(id: "logo"))
        _menuIcons = State(
            initialValue: session.spriteLibrary.uiImages(id: MenuSpritesConfig.iconsID)?
                .map(\.image) ?? []
        )
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
            await ensureMenuIcons()
            // Mid-run save *or* campaign progress (so CONTINUE survives beating a level).
            showContinue = session.shouldShowContinue
            isContentReady = true
        }
    }

    private var menuContent: some View {
        HStack(spacing: 32) {
            logoColumn

            ZStack(alignment: .bottom) {
                VStack(spacing: 24) {
                    AppTitleText(
                        text: session.currentPlayerName.map {
                            Strings.text("menu_welcome_named", ["name": $0])
                        } ?? Strings.text("menu_welcome"),
                        size: 24,
                        weight: .semibold,
                        speakID: "menu_welcome_named"
                    )
                    .accessibilityIdentifier("menu.welcome")

                    VStack(spacing: 16) {
                        if showContinue {
                            AppLargeButton(
                                title: Strings.text("menu_continue"),
                                accessibilityID: "menu.continue",
                                style: .console,
                                icon: menuIcon(.continueGame)
                            ) {
                                // Mid-run save → jump back into the world; otherwise reopen
                                // level select (where the player left after beating / quitting).
                                switch session.continueDestination {
                                case .resumeSave:
                                    router.navigate(to: .preparing(.continueSave))
                                case .levelSelect, .none:
                                    router.navigate(to: .levelSelect)
                                }
                            }
                        }

                        AppLargeButton(
                            title: Strings.text("menu_new_game"),
                            accessibilityID: "menu.newGame",
                            style: .console,
                            icon: menuIcon(.newGame)
                        ) {
                            Task {
                                await session.beginNewGame()
                                router.navigate(to: .cutscene)
                            }
                        }

                        AppLargeButton(
                            title: Strings.text("menu_settings"),
                            accessibilityID: "menu.settings",
                            style: .console,
                            icon: menuIcon(.settings)
                        ) {
                            router.navigate(to: .settings)
                        }

                        AppLargeButton(
                            title: Strings.text("menu_quit"),
                            accessibilityID: "menu.quit",
                            style: .console,
                            icon: menuIcon(.exit)
                        ) {
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

    private func menuIcon(_ icon: MenuSpritesConfig.Icon) -> UIImage? {
        guard menuIcons.indices.contains(icon.rawValue) else { return nil }
        return menuIcons[icon.rawValue]
    }

    @MainActor
    private func ensureMenuIcons() async {
        if menuIcons.count >= MenuSpritesConfig.Icon.allCases.count { return }
        if let frames = session.spriteLibrary.uiImages(id: MenuSpritesConfig.iconsID),
           frames.count >= MenuSpritesConfig.Icon.allCases.count {
            menuIcons = frames.map(\.image)
            return
        }
        guard let config = try? MenuSpritesConfig.loadFromBundle() else { return }
        for entry in config.entries {
            await session.spriteLibrary.ensureLoaded(entry.config, id: entry.id)
        }
        menuIcons = session.spriteLibrary.uiImages(id: MenuSpritesConfig.iconsID)?
            .map(\.image) ?? []
    }
}
