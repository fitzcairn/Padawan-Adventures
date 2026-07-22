import SwiftUI

struct PreparingView: View {
    let session: AppSession
    let mode: GameLaunchMode
    @State private var didStartLoad = false

    var body: some View {
        AppTitleText(text: "PREPARING FOR TAKEOFF...", size: 28, weight: .semibold)
            .padding(.horizontal)
            .appScreenBackground()
            .accessibilityIdentifier("preparing.status")
            .task {
                guard !didStartLoad else { return }
                didStartLoad = true
                await prepareAndPresentGame()
            }
    }

    @MainActor
    private func prepareAndPresentGame() async {
        let world = await GameWorldPreparer.prepareLaunch(session: session, mode: mode)
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
