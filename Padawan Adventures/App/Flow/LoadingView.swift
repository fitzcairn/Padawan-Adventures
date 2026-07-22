import SwiftUI

struct LoadingView: View {
    @Binding var session: AppSession?
    let router: FlowRouter

    var body: some View {
        AppTitleText(text: "Loading...", size: 32, weight: .semibold)
            .padding(.horizontal)
            .appScreenBackground()
            .playScreenMusic("loading")
            .accessibilityIdentifier("loading.status")
            .task {
                let loaded = await AppSession.loadResources()
                session = loaded
                router.showPlayerSelect()
            }
    }
}
