import Testing
@testable import Padawan_Adventures

struct CombatMinigameEngineTests {
    @Test func constructsInactive() {
        let engine = CombatMinigameEngine()
        #expect(!engine.isActive)
    }

    @Test func beginAndEndToggleActive() {
        var engine = CombatMinigameEngine()
        engine.begin()
        #expect(engine.isActive)
        engine.end()
        #expect(!engine.isActive)
    }
}
