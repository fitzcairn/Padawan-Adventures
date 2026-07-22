import SwiftUI

struct FlowRootView: View {
    @State private var session: AppSession?
    @State private var router: FlowRouter

    @MainActor
    init(session: AppSession? = nil, router: FlowRouter? = nil) {
        _session = State(initialValue: session)
        _router = State(initialValue: router ?? FlowRouter())
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            rootContent
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: FlowRoute.self) { route in
                    destination(for: route)
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        switch router.root {
        case .loading:
            LoadingView(session: $session, router: router)
        case .playerSelect:
            if let session {
                PlayerSelectView(session: session, router: router)
            } else {
                LoadingView(session: $session, router: router)
            }
        case .playerSelfie:
            if let session {
                PlayerSelfieView(session: session, router: router)
            } else {
                LoadingView(session: $session, router: router)
            }
        case .menu:
            if let session {
                MenuView(session: session, router: router)
            } else {
                LoadingView(session: $session, router: router)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: FlowRoute) -> some View {
        if let session {
            switch route {
            case .levelSelect:
                LevelSelectView(session: session, router: router)
            case .preparing(let mode):
                PreparingView(session: session, mode: mode)
            }
        } else {
            LoadingView(session: $session, router: router)
        }
    }
}
