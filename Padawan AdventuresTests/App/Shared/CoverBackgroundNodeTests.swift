import CoreGraphics
import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

@MainActor
struct CoverBackgroundNodeTests {
    @Test func setCoverBackgroundInstallsCoverSizedNode() async throws {
        let library = BackgroundLibrary()
        await library.ensureLoaded(named: "level_screen_bg")
        guard let image = library.uiImage(named: "level_screen_bg") else {
            Issue.record("Expected level_screen_bg to load")
            return
        }

        let scene = SKScene(size: CGSize(width: 320, height: 480))
        scene.setCoverBackground(named: "level_screen_bg", library: library)

        let node = try #require(scene.childNode(withName: CoverBackgroundNode.nodeName) as? CoverBackgroundNode)
        let expected = BackgroundCover.displaySize(image: image.size, viewport: scene.size)
        #expect(abs(node.size.width - expected.width) < 0.5)
        #expect(abs(node.size.height - expected.height) < 0.5)
        #expect(node.position == .zero)
        #expect(node.zPosition == CoverBackgroundNode.defaultZPosition)
    }

    @Test func clearCoverBackgroundRemovesNode() async {
        let library = BackgroundLibrary()
        await library.ensureLoaded(named: "level_screen_bg")
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        scene.setCoverBackground(named: "level_screen_bg", library: library)
        #expect(scene.childNode(withName: CoverBackgroundNode.nodeName) != nil)
        scene.clearCoverBackground()
        #expect(scene.childNode(withName: CoverBackgroundNode.nodeName) == nil)
    }
}
