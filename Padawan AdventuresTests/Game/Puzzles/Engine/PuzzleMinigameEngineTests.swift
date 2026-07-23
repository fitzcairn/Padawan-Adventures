import Testing
@testable import Padawan_Adventures

struct PuzzleMinigameEngineTests {
    @Test func constructsWithKindAndStartsInactive() {
        let engine = PuzzleMinigameEngine(kind: .pit)
        #expect(engine.kind == .pit)
        #expect(!engine.isActive)
    }

    @Test func beginAndEndToggleActive() {
        var engine = PuzzleMinigameEngine(kind: .gate)
        engine.begin()
        #expect(engine.isActive)
        engine.end()
        #expect(!engine.isActive)
    }

    @Test func supportsAllPuzzleKinds() {
        let kinds: [PuzzleMinigameEngine.Kind] = [.pit, .gate, .destructibleWall]
        for kind in kinds {
            let engine = PuzzleMinigameEngine(kind: kind)
            #expect(engine.kind == kind)
        }
    }
}
