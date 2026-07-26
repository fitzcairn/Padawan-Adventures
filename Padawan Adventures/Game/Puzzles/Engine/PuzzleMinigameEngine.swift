/// Scaffolding for puzzle minigame session logic (pit, gate).
struct PuzzleMinigameEngine {
    enum Kind: Equatable {
        case pit
        case gate
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
