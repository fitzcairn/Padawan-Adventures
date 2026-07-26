import Testing
@testable import Padawan_Adventures

struct LevelPlanetSpriteTests {
    @Test func catalogLevelsCarryPlanetSprites() throws {
        let levels = LevelCatalog.loadFromBundle()
        #expect(levels.count == 8)
        #expect(levels.allSatisfy { $0.sprite != nil })

        let tython = try #require(levels.first { $0.resourceName == "1-tython" }?.sprite)
        #expect(tython.root == "Sprites/UI/Levels")
        #expect(tython.chromaKey == "#000000")
        #expect(tython.chromaKeyTolerance == 2)

        let geonosis = try #require(levels.first { $0.resourceName == "8-geonosis" }?.sprite)
        guard case .sheet(let sheet, let atlas) = geonosis.animations["idle"] else {
            Issue.record("Expected geonosis idle sheet animation")
            return
        }
        // Asset filenames use the misspelling "geonisis".
        #expect(sheet == "8-geonisis")
        #expect(atlas == "8-geonisis-atlas")
    }
}
