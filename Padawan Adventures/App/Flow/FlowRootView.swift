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
        ZStack {
            screenContent
                .id(screenIdentity)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: ScreenCrossFade.duration), value: screenIdentity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppChrome.backgroundColor.ignoresSafeArea())
    }

    private var screenIdentity: FlowScreenIdentity {
        if let route = router.path.last {
            return .route(route)
        }
        return .root(router.root)
    }

    @ViewBuilder
    private var screenContent: some View {
        if let route = router.path.last {
            destination(for: route)
        } else {
            rootContent
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
            case .settings:
                SettingsView(session: session, router: router)
            case .preparing(let mode):
                PreparingView(session: session, mode: mode, router: router)
            }
        } else {
            LoadingView(session: $session, router: router)
        }
    }
}

/// Identity for cross-fading between flow screens.
private enum FlowScreenIdentity: Hashable {
    case root(FlowRoot)
    case route(FlowRoute)
}
