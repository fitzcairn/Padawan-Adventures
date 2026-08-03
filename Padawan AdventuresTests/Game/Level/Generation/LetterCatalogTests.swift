import Testing
@testable import Padawan_Adventures

struct LetterCatalogTests {
    @Test func decodesSharedPhonicsYAML() throws {
        let catalog = try LetterCatalog.decode(from: """
        phonics:
          B:
            sfx: sfx_letter_b_pronunciation
            name: sfx_letter_b_name
          a:
            sfx: sfx_letter_a_pronunciation
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
            phonics:
              ab:
                sfx: sfx_letter_ab_pronunciation
                name: sfx_letter_ab_name
            """)
        }
    }

    @Test func rejectsMissingSfxOrName() {
        #expect(throws: WorldSeedError.invalidGateLetterMatchLetters) {
            try LetterCatalog.decode(from: """
            phonics:
              a:
                name: sfx_letter_a_name
            """)
        }
        #expect(throws: WorldSeedError.invalidGateLetterMatchLetters) {
            try LetterCatalog.decode(from: """
            phonics:
              a:
                sfx: sfx_letter_a_pronunciation
            """)
        }
    }

    @Test func bundlePhonicsProvidesWallVocabulary() throws {
        let catalog = try LetterCatalog.loadFromBundle()
        #expect(catalog.letters.map(\.letter) == [
            "a", "b", "c", "d", "e", "f", "g", "h", "l", "m", "o", "p", "s", "w",
        ])
        #expect(catalog.letter(named: "a")?.pronunciation == "sfx_letter_a_pronunciation")
        #expect(catalog.letter(named: "a")?.name == "sfx_letter_a_name")
    }
}
