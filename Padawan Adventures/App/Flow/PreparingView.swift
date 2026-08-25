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
                VStack(spacing: 28) {
                    AppTitleText(
                        text: Strings.text("preparing_error"),
                        size: 28,
                        weight: .semibold
                    )
                    .accessibilityIdentifier("preparing.status")
                    AppLargeButton(title: Strings.text("button_back"), accessibilityID: "preparing.back") {
                        router.popOrShowMenu()
                    }
                    .frame(maxWidth: 280)
                }
            } else {
                LoadingScreenScaffold(
                    statusText: Strings.text("preparing_takeoff"),
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
