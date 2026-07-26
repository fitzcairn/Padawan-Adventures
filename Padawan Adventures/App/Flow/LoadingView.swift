import SwiftUI

struct LoadingView: View {
    @Binding var session: AppSession?
    let router: FlowRouter
    @State private var progress: Double = 0

    var body: some View {
        AppScreen {
            VStack(spacing: 28) {
                AppTitleText(text: "Loading...", size: 32, weight: .semibold)
                    .accessibilityIdentifier("loading.status")

                AppProgressBar(progress: progress, accessibilityID: "loading.progress")
                    .frame(maxWidth: 280)
                    .appReadableWidth()
            }
        }
        .playScreenMusic("loading")
        .task {
            let loaded = await AppSession.loadResources { value in
                progress = value
            }
            progress = 1
            session = loaded
            router.showPlayerSelect()
        }
    }
}
