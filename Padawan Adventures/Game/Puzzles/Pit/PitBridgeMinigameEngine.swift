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
        var letterPosition: GateWordPlugLetterPosition
        var words: [GateWord]
        var vocabulary: LevelVocabularyPool

        init(from bridge: PitBridgeConfig) {
            self.init(
                minWords: bridge.minWords,
                maxWords: bridge.maxWords,
                letterPosition: bridge.letterPosition,
                words: bridge.words,
                vocabulary: bridge.vocabulary
            )
        }

        init(
            minWords: Int = 2,
            maxWords: Int = 4,
            letterPosition: GateWordPlugLetterPosition = .ending,
            words: [GateWord],
            vocabulary: LevelVocabularyPool? = nil
        ) {
            let upper = max(1, maxWords)
            let lower = min(max(1, minWords), upper)
            self.minWords = lower
            self.maxWords = upper
            self.letterPosition = letterPosition
            self.words = GateWord.normalized(words)
            if let vocabulary {
                self.vocabulary = vocabulary
            } else {
                // Tests often pass words only; seed decoy graphemes from the alphabet
                // plus any units already present on those words.
                var seen = Set<String>()
                var graphemes: [GateGrapheme] = []
                for entry in self.words {
                    for g in entry.graphemes where seen.insert(g).inserted {
                        graphemes.append(GateGrapheme(grapheme: g, pronunciation: "", name: ""))
                    }
                }
                for letter in PitBridgeMinigameEngine.alphabet where seen.insert(letter).inserted {
                    graphemes.append(GateGrapheme(grapheme: letter, pronunciation: "", name: ""))
                }
                self.vocabulary = LevelVocabularyPool.singleTier(
                    words: self.words,
                    graphemes: graphemes
                )
            }
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

    /// First or last grapheme of the current word, per `config.letterPosition` — the answer.
    var currentAnswer: String {
        guard let entry = currentEntry else { return "" }
        return config.letterPosition.answerGrapheme(in: entry) ?? ""
    }

    /// Current word with the answer grapheme blanked (`ca_` for can, `__op` for stop/starting).
    var maskedPromptText: String {
        guard let entry = currentEntry else { return "" }
        return config.letterPosition.maskedText(for: entry)
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

        let poolSize = max(config.vocabulary.allWords.count, config.words.count)
        guard poolSize > 0 else {
            words = []
            return
        }

        let upper = min(config.maxWords, poolSize)
        let lower = min(max(1, config.minWords), upper)
        let n = Int.random(in: lower...upper, using: &rng)
        var sampler = LevelVocabularySampler(pool: config.vocabulary)
        words = sampler.takeWords(count: n, using: &rng)
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
        let pool = config.vocabulary.filteringGraphemes { $0.grapheme != answer.lowercased() }
        var localRng = rng
        var sampler = LevelVocabularySampler(pool: pool)
        let decoys = sampler.takeGraphemes(count: Self.choiceCount - 1, using: &localRng).map(\.grapheme)
        rng = localRng
        for decoy in decoys where !letters.contains(decoy) {
            letters.append(decoy)
            if letters.count >= Self.choiceCount { break }
        }
        // Sparse test pools may still need filler letters.
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
