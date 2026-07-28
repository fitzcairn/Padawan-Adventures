import SwiftUI

struct PreparingView: View {
    let session: AppSession
    let mode: GameLaunchMode
    let router: FlowRouter
    @State private var didStartLoad = false
    @State private var progress: Double = 0
    @State private var loadFailed = false

    var body: some View {
        AppScreen {
            VStack(spacing: 28) {
                if loadFailed {
                    AppTitleText(text: "COULD NOT LOAD ENEMIES", size: 28, weight: .semibold)
                        .accessibilityIdentifier("preparing.status")
                    AppTitleText(
                        text: "Sprite sheets failed to load. Try again from level select.",
                        size: 18,
                        weight: .regular
                    )
                    .accessibilityIdentifier("preparing.error")
                    AppLargeButton(title: "Back", accessibilityID: "preparing.back") {
                        if router.path.isEmpty {
                            router.showMenu()
                        } else {
                            router.pop()
                        }
                    }
                    .frame(maxWidth: 280)
                } else {
                    AppTitleText(text: "PREPARING FOR TAKEOFF...", size: 28, weight: .semibold)
                        .accessibilityIdentifier("preparing.status")

                    AppProgressBar(progress: progress, accessibilityID: "preparing.progress")
                        .frame(maxWidth: 280)
                        .appReadableWidth()
                }
            }
        }
        .playScreenMusic("preparing")
        .task {
            guard !didStartLoad else { return }
            didStartLoad = true
            await prepareAndPresentGame()
        }
    }

    @MainActor
    private func prepareAndPresentGame() async {
        guard let world = await GameWorldPreparer.prepareLaunch(session: session, mode: mode, onProgress: { value in
            progress = value
        }) else {
            loadFailed = true
            return
        }
        progress = 1
        let isoConfig = session.appConfig.display.makeIsometricConfig()
        let game = GameViewController(
            world: world,
            isoConfig: isoConfig,
            session: session
        )

        // Replace root so the player cannot navigate back into preparing/menu.
        let window = AppWindow.key
        window?.rootViewController = game
        window?.makeKeyAndVisible()
    }
}
