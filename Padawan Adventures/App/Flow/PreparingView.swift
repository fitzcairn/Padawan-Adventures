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
            if loadFailed {
                LoadingScreenScaffold(
                    statusText: "COULD NOT LOAD ENEMIES",
                    statusAccessibilityID: "preparing.status",
                    extra: {
                        AppTitleText(
                            text: "Sprite sheets failed to load. Try again from level select.",
                            size: 18,
                            weight: .regular
                        )
                        .accessibilityIdentifier("preparing.error")
                        AppLargeButton(title: "Back", accessibilityID: "preparing.back") {
                            router.popOrShowMenu()
                        }
                        .frame(maxWidth: 280)
                    }
                )
            } else {
                LoadingScreenScaffold(
                    statusText: "PREPARING FOR TAKEOFF...",
                    statusAccessibilityID: "preparing.status",
                    progress: progress,
                    progressAccessibilityID: "preparing.progress"
                )
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
        AppWindow.setRoot(game)
    }
}
