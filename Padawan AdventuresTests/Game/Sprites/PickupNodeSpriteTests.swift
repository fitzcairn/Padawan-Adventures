import SpriteKit
import Testing
import UIKit
@testable import Padawan_Adventures

struct PickupNodeSpriteTests {
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
            node.children.compactMap { $0 as? AnimatedSpriteNode }.first
        )
        #expect(animated.currentAnimationName == "idle")
    }

    @Test @MainActor
    func pickupNodeHeightTracksItemSpriteScale() async throws {
        let base = try ItemsConfig.loadFromBundle()
        let emitter = try #require(base.spriteConfig(id: "emitter"))
        let library = SpriteLibrary()
        await library.ensureLoaded(emitter, id: "emitter")

        let iso = AppConfig.DisplayParams(tileWidth: 80, tileHeight: 49).makeIsometricConfig()
        #expect(abs(iso.wallHeight - 80) < 0.001)

        func makePickup(scale: Double) throws -> AnimatedSpriteNode {
            var sprite = emitter
            sprite.scale = scale
            let items = ItemsConfig(items: ["emitter": ItemDefinition(sprite: sprite)])
            let node = PlaceholderFactory.pickupNode(
                kind: .treasure,
                entityID: UUID(),
                config: iso,
                spriteLibrary: library,
                itemsConfig: items,
                treasureItemID: "emitter"
            )
            return try #require(node.children.compactMap { $0 as? AnimatedSpriteNode }.first)
        }

        // Display height = wall_height × items.yaml `sprite.scale` × the world-entity multiplier.
        let fullHeight = 80 * PlaceholderFactory.spriteDisplayScaleMultiplier
        let halfHeight = fullHeight / 2

        let full = try makePickup(scale: 1.0)
        let half = try makePickup(scale: 0.5)
        #expect(abs(full.size.height - fullHeight) < 0.5)
        #expect(abs(half.size.height - halfHeight) < 0.5)
        #expect(abs(full.size.width - fullHeight * (50.0 / 125.0)) < 1.0)
        #expect(abs(half.size.width - halfHeight * (50.0 / 125.0)) < 1.0)

        // play() installs SKAction.animate(resize: false); re-fit must stick after
        // the first texture assign without needing a live SKView/RunLoop (pumping
        // the main run loop races audio finishedPlaying: callbacks from parallel tests).
        full.fitHeight(fullHeight)
        #expect(abs(full.size.height - fullHeight) < 0.5)
    }
}
