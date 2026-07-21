/// Scaffolding for combat minigame session logic (enemy encounters).
/// Placeholder overlays own UI for now; real fight rules will land here later.
struct CombatMinigameEngine {
    private(set) var isActive = false

    init() {}

    mutating func begin() {
        isActive = true
    }

    mutating func end() {
        isActive = false
    }
}
