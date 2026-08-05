import Foundation

nonisolated enum PitBridgeDropResult: Equatable, Sendable {
    /// The tile belonged in the slot; `slotIndex` is the slot just filled.
    case correct(slotIndex: Int, won: Bool)
    case incorrect
}

/// Pure pit-bridge session rules (word pick, choice bag, slot progression).
nonisolated struct PitBridgeMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var minWords: Int
        var maxWords: Int
        var words: [GateWord]

        init(from bridge: PitBridgeConfig) {
            self.init(
                minWords: bridge.minWords,
                maxWords: bridge.maxWords,
                words: bridge.words
            )
        }

        init(minWords: Int = 2, maxWords: Int = 4, words: [GateWord]) {
            let upper = max(1, maxWords)
            let lower = min(max(1, minWords), upper)
            self.minWords = lower
            self.maxWords = upper
            self.words = GateSpellingConfig.normalizedWords(words)
        }
    }

    nonisolated struct Choice: Equatable, Sendable, Identifiable {
        let id: UUID
        /// Single lowercase letter shown above the tile.
        let letter: String
        let isCorrect: Bool
    }

    /// Three tiles are offered per round.
    static let choiceCount = 3

    let config: Config
    private(set) var isActive = false
    private(set) var isFrozen = false
    /// Words for this session, in play order.
    private(set) var words: [GateWord] = []
    /// Word being answered; also the count of tiles already placed.
    private(set) var roundIndex = 0
    private(set) var choices: [Choice] = []
    private(set) var outcome: MinigameOutcome?

    private var rng: any RandomNumberGenerator

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

    var wordCount: Int { words.count }

    var currentEntry: GateWord? {
        guard roundIndex >= 0, roundIndex < words.count else { return nil }
        return words[roundIndex]
    }

    var currentWord: String {
        currentEntry?.word ?? ""
    }

    /// Illustration basename under `Sprites/Words/`.
    var currentImageName: String? {
        currentEntry?.image
    }

    /// Full-word pronunciation track from `words.yaml`.
    var currentSfx: String {
        currentEntry?.sfx ?? ""
    }

    /// Last letter of the current word — the answer.
    var currentAnswer: String {
        guard let last = currentWord.last else { return "" }
        return String(last)
    }

    /// Current word with the final letter replaced by `_` (e.g. `ca_` for `car`).
    var maskedPromptText: String {
        guard !currentWord.isEmpty else { return "" }
        return String(currentWord.dropLast()) + "_"
    }

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    mutating func begin() {
        isActive = true
        isFrozen = false
        outcome = nil
        roundIndex = 0
        choices = []

        guard !config.words.isEmpty else {
            words = []
            return
        }

        let upper = min(config.maxWords, config.words.count)
        let lower = min(max(1, config.minWords), upper)
        let n = Int.random(in: lower...upper, using: &rng)
        words = Array(config.words.shuffled(using: &rng).prefix(n))
        choices = makeChoices(for: currentAnswer)
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    mutating func accept(choiceID: UUID) -> PitBridgeDropResult? {
        guard isActive, !isFrozen, outcome == nil else { return nil }
        guard let choice = choices.first(where: { $0.id == choiceID }) else { return nil }

        guard choice.isCorrect else {
            return .incorrect
        }

        let placed = roundIndex
        roundIndex += 1
        if roundIndex >= words.count {
            isFrozen = true
            outcome = .won(starsAwarded: words.count)
            return .correct(slotIndex: placed, won: true)
        }
        choices = makeChoices(for: currentAnswer)
        return .correct(slotIndex: placed, won: false)
    }

    private mutating func makeChoices(for answer: String) -> [Choice] {
        guard !answer.isEmpty else { return [] }
        var letters = [answer]
        while letters.count < Self.choiceCount {
            let index = Int.random(in: 0..<Self.alphabet.count, using: &rng)
            let candidate = Self.alphabet[index]
            if !letters.contains(candidate) {
                letters.append(candidate)
            }
        }
        var bag = letters.map { letter in
            Choice(id: UUID(), letter: letter, isCorrect: letter == answer)
        }
        bag.shuffle(using: &rng)
        return bag
    }
}
