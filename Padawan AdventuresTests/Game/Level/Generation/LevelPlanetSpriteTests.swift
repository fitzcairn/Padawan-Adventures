import Testing
@testable import Padawan_Adventures

struct LevelPlanetSpriteTests {
    @Test func catalogLevelsCarryPlanetSprites() throws {
        let levels = LevelCatalog.loadFromBundle()
        #expect(levels.count == 8)
        #expect(levels.allSatisfy { $0.sprite != nil })

        let tython = try #require(levels.first { $0.resourceName == "1-tython" }?.sprite)
        #expect(tython.root == "Levels/1-tython")
        #expect(tython.chromaKey == "#000000")
        #expect(tython.chromaKeyTolerance == 2)

        let geonosis = try #require(levels.first { $0.resourceName == "8-geonosis" }?.sprite)
        guard case .sheet(let sheet, let atlas) = geonosis.animations["idle"] else {
            Issue.record("Expected geonosis idle sheet animation")
            return
        }
        #expect(sheet == "8-geonosis-planet-spritesheet")
        #expect(atlas == "8-geonosis-planet-atlas")
    }
}
