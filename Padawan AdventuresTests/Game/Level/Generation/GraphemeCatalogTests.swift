import Testing
@testable import Padawan_Adventures

struct GraphemeCatalogTests {
    @Test func decodesSharedGraphemesYAML() throws {
        let catalog = try GraphemeCatalog.decode(from: """
        graphemes:
          B:
            sfx: sfx_letter_b_pronunciation
            name: sfx_letter_b_name
          a:
            sfx: sfx_letter_a_pronunciation
            name: sfx_letter_a_name
        """)
        #expect(catalog.graphemes.map(\.grapheme) == ["a", "b"])
        #expect(catalog.grapheme(named: "A")?.pronunciation == "sfx_letter_a_pronunciation")
        #expect(catalog.grapheme(named: "b")?.name == "sfx_letter_b_name")
    }

    @Test func resolveNilUsesFullCatalog() throws {
        let catalog = GraphemeCatalog.fallback
        let graphemes = try catalog.resolve(ids: nil)
        #expect(graphemes.map(\.grapheme) == catalog.graphemes.map(\.grapheme))
    }

    @Test func resolveSubsetKeepsDeterministicOrder() throws {
        let catalog = GraphemeCatalog.fallback
        let graphemes = try catalog.resolve(ids: ["c", "a"])
        #expect(graphemes.map(\.grapheme) == ["a", "c"])
    }

    @Test func rejectsEmptyIDList() {
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.fallback.resolve(ids: [])
        }
    }

    @Test func rejectsInvalidGraphemeEntry() {
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.decode(from: """
            graphemes:
              "1":
                sfx: sfx_letter_1_pronunciation
                name: sfx_letter_1_name
            """)
        }
    }

    @Test func acceptsMultiLetterGraphemes() throws {
        let catalog = try GraphemeCatalog.decode(from: """
        graphemes:
          sh:
            sfx: sfx_grapheme_sh_pronunciation
            name: sfx_grapheme_sh_name
          a:
            sfx: sfx_letter_a_pronunciation
            name: sfx_letter_a_name
        """)
        #expect(catalog.graphemes.map(\.grapheme) == ["a", "sh"])
        #expect(catalog.grapheme(named: "sh")?.name == "sfx_grapheme_sh_name")
    }

    @Test func rejectsMissingSfxOrName() {
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.decode(from: """
            graphemes:
              a:
                name: sfx_letter_a_name
            """)
        }
        #expect(throws: WorldSeedError.invalidGateGraphemeMatchGraphemes) {
            try GraphemeCatalog.decode(from: """
            graphemes:
              a:
                sfx: sfx_letter_a_pronunciation
            """)
        }
    }

    @Test func bundleGraphemesProvideWallVocabulary() throws {
        let catalog = try GraphemeCatalog.loadFromBundle()
        #expect(catalog.graphemes.map(\.grapheme) == [
            "a", "ai", "ay", "b", "bl", "br", "c", "cr", "d", "e", "ea", "ee",
            "f", "ff", "fl", "fr", "g", "h", "i", "igh", "j", "k", "l", "ll",
            "m", "mp", "n", "nd", "nt", "o", "oa", "ow", "p", "pl", "q", "qu",
            "r", "s", "sh", "sl", "sn", "sp", "ss", "st", "t", "tr", "u", "v",
            "w", "x", "y", "z", "zz",
        ])
        #expect(catalog.grapheme(named: "a")?.pronunciation == "sfx_letter_a_pronunciation")
        #expect(catalog.grapheme(named: "a")?.name == "sfx_letter_a_name")
        #expect(catalog.grapheme(named: "sh")?.name == "sfx_grapheme_sh_name")
    }
}
