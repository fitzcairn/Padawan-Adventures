import Testing
@testable import Padawan_Adventures

@MainActor
struct CutsceneAssetsTests {
    @Test func bundledCutsceneSheetsLoad() async throws {
        let config = try CutsceneSpritesConfig.loadFromBundle()
        let library = SpriteLibrary()
        for entry in config.entries {
            #expect(entry.config.root == "Sprites/UI/Cutscene")
            await library.ensureLoaded(entry.config, id: entry.id)
            #expect(library.isLoaded(id: entry.id))
            #expect(library.animation(id: entry.id, named: "idle")?.frames.count == 25)
        }
    }

    @Test func cutsceneMovieIsBundledAndPreloads() async {
        #expect(CutsceneVideo.url() != nil)
        let video = CutsceneVideo()
        await video.preload()
        #expect(video.player != nil)
    }
}
