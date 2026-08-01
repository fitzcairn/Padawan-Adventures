import Testing
@testable import Padawan_Adventures

struct LetterCatalogTests {
    @Test func decodesSharedLettersYAML() throws {
        let catalog = try LetterCatalog.decode(from: """
        letters:
          B:
            pronunciation: sfx_letter_b_pronunciation
            name: sfx_letter_b_name
          a:
            pronunciation: sfx_letter_a_pronunciation
            name: sfx_letter_a_name
        """)
        #expect(catalog.letters.map(\.letter) == ["a", "b"])
        #expect(catalog.letter(named: "A")?.pronunciation == "sfx_letter_a_pronunciation")
        #expect(catalog.letter(named: "b")?.name == "sfx_letter_b_name")
    }

    @Test func resolveNilUsesFullCatalog() throws {
        let catalog = LetterCatalog.fallback
        let letters = try catalog.resolve(ids: nil)
        #expect(letters.map(\.letter) == catalog.letters.map(\.letter))
    }

    @Test func resolveSubsetKeepsDeterministicOrder() throws {
        let catalog = LetterCatalog.fallback
        let letters = try catalog.resolve(ids: ["c", "a"])
        #expect(letters.map(\.letter) == ["a", "c"])
    }

    @Test func rejectsEmptyIDList() {
        #expect(throws: WorldSeedError.invalidGateLetterMatchLetters) {
            try LetterCatalog.fallback.resolve(ids: [])
        }
    }

    @Test func rejectsInvalidLetterEntry() {
        #expect(throws: WorldSeedError.invalidGateLetterMatchLetters) {
            try LetterCatalog.decode(from: """
            letters:
              ab:
                pronunciation: sfx_letter_ab_pronunciation
                name: sfx_letter_ab_name
            """)
        }
    }

    @Test func derivesEmptyEntriesAndHonorsOverrides() throws {
        let catalog = try LetterCatalog.decode(from: """
        letters:
          a:
          b:
            name: custom_b_name
        """)
        #expect(catalog.letter(named: "a")?.pronunciation == "sfx_letter_a_pronunciation")
        #expect(catalog.letter(named: "a")?.name == "sfx_letter_a_name")
        #expect(catalog.letter(named: "b")?.pronunciation == "sfx_letter_b_pronunciation")
        #expect(catalog.letter(named: "b")?.name == "custom_b_name")
    }

    @Test func bundleLettersProvidesWallVocabulary() throws {
        let catalog = try LetterCatalog.loadFromBundle()
        #expect(catalog.letters.map(\.letter) == ["a", "b", "c", "d", "e", "f", "g", "h", "o", "s"])
        #expect(catalog.letter(named: "a")?.pronunciation == "sfx_letter_a_pronunciation")
    }
}
