import Testing
@testable import Padawan_Adventures

struct WordCatalogTests {
    @Test func decodesSharedWordsYAML() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          CAT:
            spelling: sfx_word_cat
            progressive:
              c: sfx_word_cat_c
              ca: sfx_word_cat_ca
              cat: sfx_word_cat_cat
          dog:
            spelling: sfx_word_dog
            progressive:
              d: sfx_word_dog_d
              do: sfx_word_dog_do
              dog: sfx_word_dog_dog
        """)
        #expect(catalog.words.map(\.word) == ["cat", "dog"])
        #expect(catalog.word(named: "CAT")?.spelling == "sfx_word_cat")
        #expect(catalog.word(named: "cat")?.progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca")
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

    @Test func rejectsMissingProgressivePrefix() {
        #expect(throws: WorldSeedError.invalidGateWords) {
            try WordCatalog.decode(from: """
            words:
              cat:
                spelling: sfx_word_cat
                progressive:
                  c: sfx_word_cat_c
                  cat: sfx_word_cat_cat
            """)
        }
    }

    @Test func bundleWordsProvidesGateVocabulary() throws {
        let catalog = try WordCatalog.loadFromBundle()
        #expect(catalog.words.map(\.word).contains("gate"))
        #expect(catalog.words.contains {
            $0.word == "cat"
                && $0.spelling == "sfx_word_cat"
                && $0.progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca"
        })
    }
}
