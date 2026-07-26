import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

struct SpriteIconLibraryTests {
    @Test @MainActor
    func loadsFirstFrameFromBundledTreasureItem() async throws {
        let items = try ItemsConfig.loadFromBundle()
        let sprite = try #require(items.spriteConfig(id: "emitter"))
        let library = SpriteIconLibrary()
        await library.ensureLoaded(sprite, id: "emitter")
        let image = try #require(library.uiImage(id: "emitter"))
        #expect(library.count == 1)
        #expect(image.size.width > 1)
        #expect(image.size.height > 1)
    }

    @Test @MainActor
    func unknownAnimationLeavesCacheEmpty() async throws {
        let items = try ItemsConfig.loadFromBundle()
        let sprite = try #require(items.spriteConfig(id: "emitter"))
        let library = SpriteIconLibrary()
        await library.ensureLoaded(sprite, id: "emitter", animationName: "missing-clip")
        #expect(library.uiImage(id: "emitter") == nil)
        #expect(library.count == 0)
    }

    @Test @MainActor
    func spriteLibraryLoadsEmitterForInWorldPickup() async throws {
        let items = try ItemsConfig.loadFromBundle()
        let sprite = try #require(items.spriteConfig(id: "emitter"))
        #expect(sprite.chromaKey == nil)
        let library = SpriteLibrary()
        await library.ensureLoaded(sprite, id: "emitter")
        let animation = try #require(library.animation(id: "emitter", named: "idle"))
        #expect(animation.frames.count == 25)
        #expect(animation.frames[0].texture.size().width > 1)
        #expect(animation.frames[0].texture.size().height > 1)

        let node = PlaceholderFactory.pickupNode(
            kind: .treasure,
            entityID: UUID(),
            config: IsometricConfig(),
            spriteLibrary: library,
            itemsConfig: items,
            treasureItemID: "emitter"
        )
        let animated = try #require(
            node.children.first as? AnimatedSpriteNode
        )
        #expect(animated.currentAnimationName == "idle")
    }
}
