import Testing
@testable import Padawan_Adventures

@MainActor
struct FlowRouterTests {
    @Test func defaultsToLoadingWithEmptyPath() {
        let router = FlowRouter()
        #expect(router.root == .loading)
        #expect(router.path.isEmpty)
    }

    @Test func showPlayerSelectResetsPath() {
        let router = FlowRouter(root: .loading, path: [.levelSelect])
        router.showPlayerSelect()
        #expect(router.root == .playerSelect)
        #expect(router.path.isEmpty)
    }

    @Test func showMenuResetsPath() {
        let router = FlowRouter(root: .playerSelect, path: [.preparing(.newGame)])
        router.showMenu()
        #expect(router.root == .menu)
        #expect(router.path.isEmpty)
    }

    @Test func showPlayerSelfieResetsPath() {
        let router = FlowRouter(root: .playerSelect, path: [.levelSelect])
        router.showPlayerSelfie()
        #expect(router.root == .playerSelfie)
        #expect(router.path.isEmpty)
    }

    @Test func navigateAppendsRoutes() {
        let router = FlowRouter(root: .menu)
        router.navigate(to: .levelSelect)
        router.navigate(to: .preparing(.newGame))
        #expect(router.path == [.levelSelect, .preparing(.newGame)])
    }

    @Test func continueNavigatesToPreparingContinueSave() {
        let router = FlowRouter(root: .menu)
        router.navigate(to: .preparing(.continueSave))
        #expect(router.path == [.preparing(.continueSave)])
    }

    @Test func popRemovesLastRoute() {
        let router = FlowRouter(root: .menu, path: [.levelSelect, .preparing(.newGame)])
        router.pop()
        #expect(router.path == [.levelSelect])
        router.pop()
        #expect(router.path.isEmpty)
        router.pop()
        #expect(router.path.isEmpty)
    }

    @Test func postGameRouterStartsAtMenuWithLevelSelect() {
        let router = FlowRouter.postGameRouter()
        #expect(router.root == .menu)
        #expect(router.path == [.levelSelect])
    }
}
