import SwiftUI

struct PreparingView: View {
    let session: AppSession
    let mode: GameLaunchMode
    @State private var didStartLoad = false
    @State private var progress: Double = 0

    var body: some View {
        AppScreen {
            VStack(spacing: 28) {
                AppTitleText(text: "PREPARING FOR TAKEOFF...", size: 28, weight: .semibold)
                    .accessibilityIdentifier("preparing.status")

                AppProgressBar(progress: progress, accessibilityID: "preparing.progress")
                    .frame(maxWidth: 280)
                    .appReadableWidth()
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
        let world = await GameWorldPreparer.prepareLaunch(session: session, mode: mode) { value in
            progress = value
        }
        progress = 1
        let isoConfig = session.seedConfig.display.makeIsometricConfig()
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
