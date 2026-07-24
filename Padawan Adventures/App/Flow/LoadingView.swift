import SwiftUI

struct LoadingView: View {
    @Binding var session: AppSession?
    let router: FlowRouter

    var body: some View {
        AppScreen {
            AppTitleText(text: "Loading...", size: 32, weight: .semibold)
                .accessibilityIdentifier("loading.status")
        }
        .playScreenMusic("loading")
        .task {
            let loaded = await AppSession.loadResources()
            session = loaded
            router.showPlayerSelect()
        }
    }
}
