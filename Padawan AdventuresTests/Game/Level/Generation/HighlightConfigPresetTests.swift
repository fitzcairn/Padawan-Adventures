import Testing
@testable import Padawan_Adventures

struct HighlightConfigPresetTests {
    @Test func treasureGoldMatchesHistoricValues() {
        let gold = HighlightConfig.treasureGold
        #expect(gold.color == "#FFD54F")
        #expect(gold.birthRate == 22)
        #expect(gold.lifetime == 1.1)
        #expect(gold.radius == 0.45)
        #expect(gold.particleSize == 0.12)
        #expect(gold.alpha == 0.85)
        #expect(gold.yOffset == 0.45)
    }

    @Test func everyTreasureUsesTheSharedPreset() throws {
        let items = try ItemsConfig.loadFromBundle()
        let treasureIDs = LevelCatalog.loadFromBundle().compactMap(\.treasure)
        #expect(!treasureIDs.isEmpty)
        for id in treasureIDs {
            #expect(items.highlight(id: id) == .treasureGold, "Expected treasure_gold for \(id)")
        }
    }

    @Test func unknownHighlightPresetThrows() {
        #expect(throws: ItemsConfigError.self) {
            try ItemsConfig.decode(from: """
            x:
              highlight: not_a_real_preset
            """)
        }
    }

    @Test func inlineHighlightMappingStillDecodes() throws {
        let items = try ItemsConfig.decode(from: """
        custom:
          highlight:
            color: "#112233"
            birth_rate: 10
            lifetime: 0.5
            radius: 0.2
            particle_size: 0.1
            alpha: 0.5
            y_offset: 0.3
        """)
        let highlight = try #require(items.highlight(id: "custom"))
        #expect(highlight.color == "#112233")
        #expect(highlight.birthRate == 10)
    }

    @Test func treasureGoldPresetNameDecodes() throws {
        let items = try ItemsConfig.decode(from: """
        x:
          highlight: treasure_gold
        """)
        #expect(items.highlight(id: "x") == .treasureGold)
    }
}
