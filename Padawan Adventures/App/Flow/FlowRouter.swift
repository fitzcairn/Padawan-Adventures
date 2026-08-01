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
        setRoot(.playerSelect)
    }

    func showPlayerSelfie() {
        setRoot(.playerSelfie)
    }

    func showMenu() {
        setRoot(.menu)
    }

    func navigate(to route: FlowRoute) {
        GameLogger.mark(.flow, "navigate to \(route) (from \(describeStack()))")
        path.append(route)
    }

    /// Replaces the cutscene with the planet map so Back cannot return to it.
    func showLevelSelect() {
        GameLogger.mark(.flow, "showLevelSelect (from \(describeStack()))")
        path = [.levelSelect]
    }

    func pop() {
        guard !path.isEmpty else { return }
        GameLogger.mark(.flow, "pop \(path[path.count - 1]) (from \(describeStack()))")
        path.removeLast()
    }

    /// Pops one route when the stack is non-empty; otherwise returns to the menu root.
    func popOrShowMenu() {
        if path.isEmpty {
            showMenu()
        } else {
            pop()
        }
    }

    private func setRoot(_ newRoot: FlowRoot) {
        GameLogger.mark(.flow, "root \(root) -> \(newRoot) (clearing \(describeStack()))")
        root = newRoot
        path = []
    }

    private func describeStack() -> String {
        "\(root)+[\(path.map(String.init(describing:)).joined(separator: ", "))]"
    }

    /// Post-game stack: menu root with level select pushed.
    static func postGameRouter() -> FlowRouter {
        FlowRouter(root: .menu, path: [.levelSelect])
    }
}
