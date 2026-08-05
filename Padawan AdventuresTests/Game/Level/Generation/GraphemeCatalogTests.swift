import Testing
@testable import Padawan_Adventures

struct GraphemeCatalogTests {
    @Test func decodesSharedPhonicsYAML() throws {
        let catalog = try GraphemeCatalog.decode(from: """
        graphemes:
          B:
            sfx: sfx_grapheme_b_pronunciation
            name: sfx_grapheme_b_name
          a:
            sfx: sfx_grapheme_a_pronunciation
            name: sfx_grapheme_a_name
        """)
        #expect(catalog.graphemes.map(.grapheme) == ["a", "b"])
        #expect(catalog.grapheme(named: "A")?.pronunciation == "sfx_grapheme_a_pronunciation")
        #expect(catalog.grapheme(named: "b")?.name == "sfx_grapheme_b_name")
    }

    @Test func resolveNilUsesFullCatalog() throws {
        let catalog = GraphemeCatalog.fallback
        let graphemes = try catalog.resolve(ids: nil)
        #expect(letters.map(.grapheme) == catalog.graphemes.map(.grapheme))
    }

    @Test func resolveSubsetKeepsDeterministicOrder() throws {
        let catalog = GraphemeCatalog.fallback
        let graphemes = try catalog.resolve(ids: ["c", "a"])
        #expect(letters.map(.grapheme) == ["a", "c"])
    }

    @Test func rejectsEmptyIDList() {
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.fallback.resolve(ids: [])
        }
    }

    @Test func rejectsInvalidLetterEntry() {
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.decode(from: """
            graphemes:
              ab:
                sfx: sfx_grapheme_ab_pronunciation
                name: sfx_grapheme_ab_name
            """)
        }
    }

    @Test func rejectsMissingSfxOrName() {
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.decode(from: """
            graphemes:
              a:
                name: sfx_grapheme_a_name
            """)
        }
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.decode(from: """
            graphemes:
              a:
                sfx: sfx_grapheme_a_pronunciation
            """)
        }
    }

    @Test func bundlePhonicsProvidesWallVocabulary() throws {
        let catalog = try GraphemeCatalog.loadFromBundle()
        #expect(catalog.graphemes.map(.grapheme) == [
            "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
            "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        ])
        #expect(catalog.grapheme(named: "a")?.pronunciation == "sfx_grapheme_a_pronunciation")
        #expect(catalog.grapheme(named: "a")?.name == "sfx_grapheme_a_name")
    }
}
