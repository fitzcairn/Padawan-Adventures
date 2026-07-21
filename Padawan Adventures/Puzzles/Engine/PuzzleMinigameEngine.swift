/// Scaffolding for puzzle minigame session logic (pit, gate, destructible wall).
/// Placeholder overlays own UI for now; real puzzle rules will land here later.
struct PuzzleMinigameEngine {
    enum Kind: Equatable {
        case pit
        case gate
        case destructibleWall
    }

    let kind: Kind
    private(set) var isActive = false

    init(kind: Kind) {
        self.kind = kind
    }

    mutating func begin() {
        isActive = true
    }

    mutating func end() {
        isActive = false
    }
}
