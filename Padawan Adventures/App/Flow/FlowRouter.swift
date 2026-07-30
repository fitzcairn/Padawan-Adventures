import Foundation

enum FlowRoot: Hashable, Sendable {
    case loading
    case playerSelect
    case playerSelfie
    case menu
}

enum FlowRoute: Hashable, Sendable {
    case levelSelect
    case settings
    case cutscene
    case preparing(GameLaunchMode)
}

@MainActor
@Observable
final class FlowRouter {
    var root: FlowRoot
    var path: [FlowRoute]

    init(root: FlowRoot = .loading, path: [FlowRoute] = []) {
        self.root = root
        self.path = path
    }

    func showPlayerSelect() {
        root = .playerSelect
        path = []
    }

    func showPlayerSelfie() {
        root = .playerSelfie
        path = []
    }

    func showMenu() {
        root = .menu
        path = []
    }

    func navigate(to route: FlowRoute) {
        path.append(route)
    }

    /// Replaces the cutscene with the planet map so Back cannot return to it.
    func showLevelSelect() {
        path = [.levelSelect]
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Post-game stack: menu root with level select pushed.
    static func postGameRouter() -> FlowRouter {
        FlowRouter(root: .menu, path: [.levelSelect])
    }
}
