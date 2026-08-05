import Testing
@testable import Padawan_Adventures

struct WordCatalogTests {
    @Test func decodesSharedWordsYAML() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          CAT:
            image: cat
            sfx: sfx_word_cat
            graphemes: [c, a, t]
          dog:
            sfx: sfx_word_dog
            graphemes: [d, o, g]
        """)
        #expect(catalog.words.map(\.word) == ["cat", "dog"])
        #expect(catalog.word(named: "CAT")?.sfx == "sfx_word_cat")
        #expect(catalog.word(named: "CAT")?.image == "cat")
        #expect(catalog.word(named: "dog")?.image == nil)
        #expect(catalog.word(named: "cat")?.graphemes == ["c", "a", "t"])
    }

    @Test func resolveNilUsesFullCatalog() throws {
        let catalog = WordCatalog.fallback
        let words = try catalog.resolve(ids: nil)
        #expect(words.map(\.word) == catalog.words.map(\.word))
    }

    @Test func resolveSubsetKeepsDeterministicOrder() throws {
        let catalog = WordCatalog.fallback
        let words = try catalog.resolve(ids: ["star", "cat"])
        #expect(words.map(\.word) == ["cat", "star"])
    }

    @Test func rejectsEmptyIDList() {
        #expect(throws: WorldSeedError.invalidGateWords) {
            try WordCatalog.fallback.resolve(ids: [])
        }
    }

    @Test func rejectsMissingSfx() {
        #expect(throws: WorldSeedError.invalidGateWords) {
            try WordCatalog.decode(from: """
            words:
              cat:
                image: cat
                graphemes: [c, a, t]
            """)
        }
    }

    @Test func rejectsMissingOrMismatchedGraphemes() {
        #expect(throws: WorldSeedError.invalidGateWords) {
            try WordCatalog.decode(from: """
            words:
              cat:
                sfx: sfx_word_cat
            """)
        }
        #expect(throws: WorldSeedError.invalidGateWords) {
            try WordCatalog.decode(from: """
            words:
              cat:
                sfx: sfx_word_cat
                graphemes: [d, o, g]
            """)
        }
    }

    @Test func requiresExplicitGraphemes() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          cat:
            sfx: sfx_word_cat
            graphemes: [c, a, t]
          dog:
            sfx: custom_dog
            graphemes: [d, o, g]
        """)
        #expect(catalog.word(named: "cat")?.sfx == "sfx_word_cat")
        #expect(catalog.word(named: "cat")?.image == nil)
        #expect(catalog.word(named: "cat")?.graphemes == ["c", "a", "t"])
        #expect(catalog.word(named: "dog")?.sfx == "custom_dog")
        #expect(catalog.word(named: "dog")?.graphemes == ["d", "o", "g"])
    }

    @Test func bundleWordsProvidesGateVocabulary() throws {
        let catalog = try WordCatalog.loadFromBundle()
        #expect(catalog.words.map(\.word).contains("gate"))
        #expect(catalog.words.contains {
            $0.word == "cat"
                && $0.image == "cat"
                && $0.sfx == "sfx_word_cat"
                && $0.graphemes == ["c", "a", "t"]
        })
        #expect(catalog.words.contains {
            $0.word == "gate"
                && $0.image == nil
                && $0.sfx == "sfx_word_gate"
        })
    }
}
