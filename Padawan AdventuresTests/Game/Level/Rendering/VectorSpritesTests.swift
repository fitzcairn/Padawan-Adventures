import Foundation
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
struct VectorSpritesTests {
    @Test func bundledFlyoverSheetLoads() async throws {
        let config = try VectorSpritesConfig.loadFromBundle()
        let library = SpriteLibrary()
        for entry in config.entries {
            await library.ensureLoaded(entry.config, id: entry.id)
            #expect(library.isLoaded(id: entry.id))
        }
        let fly = try #require(
            library.animation(id: VectorSpritesConfig.libraryID, named: VectorSpritesConfig.flyAnimation)
        )
        #expect(fly.frames.count == 25)
        #expect(fly.flipsHorizontally == false)
        let expectedLoop: TimeInterval = 25 / 15
        let loopSum = fly.frames.reduce(0.0) { $0 + $1.duration }
        #expect(abs(loopSum - expectedLoop) < 0.000_1)

        let ship = VectorStrafeVFX.makeShip(library: library)
        #expect(ship.name == "vectorShip")
        #expect(ship is AnimatedSpriteNode)
    }

    @Test func missingLibraryFallsBackToPlaceholder() {
        let ship = VectorStrafeVFX.makeShip(library: nil)
        #expect(ship.name == "vectorShip")
        #expect(!(ship is AnimatedSpriteNode))
    }
}
