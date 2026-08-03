import Testing
@testable import Padawan_Adventures

@MainActor
struct BackgroundLibraryTests {
    @Test func loadsLevelScreenBackgroundFromBundle() async {
        let library = BackgroundLibrary()
        await library.ensureLoaded(named: "level_screen_bg")
        #expect(library.uiImage(named: "level_screen_bg") != nil)
        #expect(library.count == 1)
    }

    @Test func ensureLoadedIsIdempotent() async {
        let library = BackgroundLibrary()
        await library.ensureLoaded(named: "level_screen_bg")
        await library.ensureLoaded(named: "level_screen_bg")
        #expect(library.count == 1)
    }

    @Test func missingBackgroundIsSkipped() async {
        let library = BackgroundLibrary()
        await library.ensureLoaded(named: "does_not_exist_bg")
        #expect(library.uiImage(named: "does_not_exist_bg") == nil)
        #expect(library.count == 0)
    }

    @Test func screenBackgroundNamesIncludeLevelSelect() {
        let names = BackgroundLibrary.screenBackgroundNames()
        #expect(names.contains("level_screen_bg"))
    }

    @Test func uniqueNamesDedupesAndDropsEmpties() {
        #expect(
            BackgroundLibrary.uniqueNames([" a ", "a", "", "b", "  "]) == ["a", "b"]
        )
    }

    @Test func retainDropsNonKeptNamesAndRestoresResidentBytes() async {
        let library = BackgroundLibrary()
        await library.ensureLoaded(named: "level_screen_bg")
        let beforeCount = library.count
        let beforeBytes = library.residentBytes
        #expect(beforeCount >= 1)
        #expect(beforeBytes > 0)

        library.retain(names: [])
        #expect(library.count == 0)
        #expect(library.residentBytes == 0)
        #expect(library.uiImage(named: "level_screen_bg") == nil)

        await library.ensureLoaded(named: "level_screen_bg")
        library.retain(names: ["level_screen_bg"])
        #expect(library.count == 1)
        #expect(library.residentBytes == beforeBytes)
    }
}
