import Testing
@testable import Padawan_Adventures

struct GraphemeSoundCatalogTests {
    @Test func nameTrackUsesLowercaseLetter() {
        #expect(GraphemeSoundCatalog.nameTrackID(for: "B") == "sfx_grapheme_b_name")
        #expect(GraphemeSoundCatalog.nameTrackID(for: "a") == "sfx_grapheme_a_name")
        #expect(GraphemeSoundCatalog.pronunciationTrackID(for: "C") == "sfx_grapheme_c_pronunciation")
    }

    @Test func rejectsNonLetters() {
        #expect(GraphemeSoundCatalog.nameTrackID(for: "") == nil)
        #expect(GraphemeSoundCatalog.nameTrackID(for: "1") == nil)
    }
}
