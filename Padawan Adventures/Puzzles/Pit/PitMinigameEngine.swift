import Foundation

nonisolated enum PitOutcome: Equatable, Sendable {
    case won(starsAwarded: Int)
    case lost
}

nonisolated enum PitEngineEvent: Equatable, Sendable {
    case timerTick
    case won
    case lost
}

nonisolated enum PitLetterTapResult: Equatable, Sendable {
    /// Letter matched the next required character; `prefix` is the solved prefix so far.
    case correct(prefix: String, won: Bool)
    /// Letter was tappable but not the next required character.
    case incorrect
}

/// Pure pit puzzle session rules (word pick, letter bag, timer, hop progression).
nonisolated struct PitMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var timerSeconds: Double
        var words: [GateWord]

        init(from puzzle: PitPuzzleConfig) {
            timerSeconds = puzzle.timerSeconds
            words = puzzle.words
        }

        init(
            timerSeconds: Double,
            words: [GateWord]
        ) {
            self.timerSeconds = timerSeconds
            self.words = words.map {
                GateWord(
                    word: $0.word.lowercased(),
                    spelling: $0.spelling,
                    progressive: $0.progressive
                )
            }
        }
    }

    nonisolated struct LetterToken: Equatable, Sendable, Identifiable {
        let id: UUID
        /// Single lowercase letter.
        let letter: String
    }

    let config: Config
    private(set) var isActive = false
    private(set) var elapsed: Double = 0
    private(set) var remainingTime: Double
    private(set) var targetWord: String = ""
    private(set) var targetEntry: GateWord = .fallbackEntry(word: "star")
    private(set) var letters: [LetterToken] = []
    /// Word-occurrence token IDs in spelling order (excludes decoys).
    private(set) var wordLetterIDs: [UUID] = []
    private(set) var nextLetterIndex = 0
    private(set) var spentLetterIDs: Set<UUID> = []
    private(set) var outcome: PitOutcome?
    private(set) var isFrozen = false

    private var lastDisplayedSecond: Int
    private var rng: any RandomNumberGenerator

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

    /// Spelling track for the chosen word (open / after progressive / win).
    var targetSoundTrackID: String { targetEntry.spelling }

    /// Prefix solved so far (empty when nothing correct yet).
    var solvedPrefix: String {
        guard nextLetterIndex > 0 else { return "" }
        return String(targetWord.prefix(nextLetterIndex))
    }

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.remainingTime = config.timerSeconds
        self.lastDisplayedSecond = Int(ceil(config.timerSeconds))
        self.rng = rng
    }

    mutating func begin() {
        isActive = true
        isFrozen = false
        elapsed = 0
        remainingTime = config.timerSeconds
        outcome = nil
        nextLetterIndex = 0
        spentLetterIDs = []
        wordLetterIDs = []
        lastDisplayedSecond = Int(ceil(config.timerSeconds))
        let picked = pickTargetEntry()
        targetEntry = picked
        targetWord = picked.word
        letters = buildLetterBag(for: targetWord)
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    var hasLost: Bool { remainingTime <= 0 }

    func isSpent(_ id: UUID) -> Bool {
        spentLetterIDs.contains(id)
    }

    func letter(id: UUID) -> LetterToken? {
        letters.first { $0.id == id }
    }

    /// Advance simulation by `dt`. Returns events for the scene/HUD to react to.
    mutating func tick(dt: Double) -> [PitEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }

        var events: [PitEngineEvent] = []
        elapsed += dt
        remainingTime = max(0, config.timerSeconds - elapsed)

        let displayedSecond = max(0, Int(ceil(remainingTime - 1e-9)))
        if displayedSecond < lastDisplayedSecond {
            if displayedSecond <= 5, lastDisplayedSecond > 0 {
                events.append(.timerTick)
            }
            lastDisplayedSecond = displayedSecond
        }

        if hasLost {
            isFrozen = true
            outcome = .lost
            events.append(.lost)
        }

        return events
    }

    /// Evaluate a letter tap after the scene has confirmed neighbor range.
    mutating func acceptLetter(id: UUID) -> PitLetterTapResult? {
        guard isActive, !isFrozen, outcome == nil else { return nil }
        guard let token = letter(id: id), !spentLetterIDs.contains(id) else { return nil }
        guard nextLetterIndex < targetWord.count else { return nil }

        let expected = String(targetWord[targetWord.index(targetWord.startIndex, offsetBy: nextLetterIndex)])
        guard token.letter == expected else {
            return .incorrect
        }

        spentLetterIDs.insert(id)
        nextLetterIndex += 1
        let prefix = solvedPrefix
        if nextLetterIndex >= targetWord.count {
            isFrozen = true
            outcome = .won(starsAwarded: targetWord.count)
            return .correct(prefix: prefix, won: true)
        }
        return .correct(prefix: prefix, won: false)
    }

    private mutating func pickTargetEntry() -> GateWord {
        let words = config.words
        guard !words.isEmpty else {
            return .fallbackEntry(word: "star")
        }
        let index = Int.random(in: 0..<words.count, using: &rng)
        return words[index]
    }

    /// One sprite per word occurrence, plus `1...uniqueCount` decoys not in the word set.
    private mutating func buildLetterBag(for word: String) -> [LetterToken] {
        let wordTokens: [LetterToken] = word.map { character in
            LetterToken(id: UUID(), letter: String(character).lowercased())
        }
        wordLetterIDs = wordTokens.map(\.id)

        var bag = wordTokens
        let uniqueLetters = Set(bag.map(\.letter))
        let uniqueCount = max(uniqueLetters.count, 1)
        let decoyCount = Int.random(in: 1...uniqueCount, using: &rng)
        let decoyPool = Self.alphabet.filter { !uniqueLetters.contains($0) }
        if !decoyPool.isEmpty {
            for _ in 0..<decoyCount {
                let index = Int.random(in: 0..<decoyPool.count, using: &rng)
                bag.append(LetterToken(id: UUID(), letter: decoyPool[index]))
            }
        }

        bag.shuffle(using: &rng)
        return bag
    }
}
