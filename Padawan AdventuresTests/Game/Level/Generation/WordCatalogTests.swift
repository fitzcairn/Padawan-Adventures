import Testing
@testable import Padawan_Adventures

struct WordCatalogTests {
    @Test func decodesSharedWordsYAML() throws {
        let catalog = try WordCatalog.decode(from: """
        words:
          CAT:
            image: cat
            sfx: sfx_word_cat
            progressive:
              c: sfx_word_cat_c
              ca: sfx_word_cat_ca
              cat: sfx_word_cat_cat
          dog:
            sfx: sfx_word_dog
            progressive:
              d: sfx_word_dog_d
              do: sfx_word_dog_do
              dog: sfx_word_dog_dog
        """)
        #expect(catalog.words.map(\.word) == ["cat", "dog"])
        #expect(catalog.word(named: "CAT")?.sfx == "sfx_word_cat")
        #expect(catalog.word(named: "CAT")?.image == "cat")
        #expect(catalog.word(named: "dog")?.image == nil)
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

    @Test func derivesEmptyEntriesAndMergesPartialOverrides() throws {
        let catalog = try WordCatalog.decode(from: """
        fx_prefix: sfx_word_
        words:
          cat:
          dog:
            sfx: custom_dog
            progressive:
              d: custom_dog_d
        """)
        #expect(catalog.word(named: "cat")?.sfx == "sfx_word_cat")
        #expect(catalog.word(named: "cat")?.image == nil)
        #expect(catalog.word(named: "cat")?.progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca")
        #expect(catalog.word(named: "dog")?.sfx == "custom_dog")
        #expect(catalog.word(named: "dog")?.progressiveTrack(forPrefix: "d") == "custom_dog_d")
        #expect(catalog.word(named: "dog")?.progressiveTrack(forPrefix: "do") == "sfx_word_dog_do")
    }

    @Test func bundleWordsProvidesGateVocabulary() throws {
        let catalog = try WordCatalog.loadFromBundle()
        #expect(catalog.words.map(\.word).contains("gate"))
        #expect(catalog.words.contains {
            $0.word == "cat"
                && $0.image == "cat"
                && $0.sfx == "sfx_word_cat"
                && $0.progressiveTrack(forPrefix: "ca") == "sfx_word_cat_ca"
        })
        #expect(catalog.words.contains {
            $0.word == "gate"
                && $0.image == nil
                && $0.sfx == "sfx_word_gate"
        })
    }
}
