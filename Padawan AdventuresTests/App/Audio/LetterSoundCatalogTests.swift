import Testing
@testable import Padawan_Adventures

struct LetterSoundCatalogTests {
    @Test func nameTrackUsesLowercaseLetter() {
        #expect(LetterSoundCatalog.nameTrackID(for: "B") == "sfx_letter_b_name")
        #expect(LetterSoundCatalog.nameTrackID(for: "a") == "sfx_letter_a_name")
        #expect(LetterSoundCatalog.pronunciationTrackID(for: "C") == "sfx_letter_c_pronunciation")
    }

    @Test func rejectsNonLetters() {
        #expect(LetterSoundCatalog.nameTrackID(for: "") == nil)
        #expect(LetterSoundCatalog.nameTrackID(for: "1") == nil)
    }
}
