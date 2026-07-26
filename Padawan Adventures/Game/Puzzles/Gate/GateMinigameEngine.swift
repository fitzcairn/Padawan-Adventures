import Foundation

nonisolated enum GateOutcome: Equatable, Sendable {
    case won(starsAwarded: Int)
    case lost
}

nonisolated enum GateEngineEvent: Equatable, Sendable {
    case timerTick
    case won
    case lost
}

/// Pure gate puzzle session rules (word pick, letter bag, timer, staging win check).
nonisolated struct GateMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var timerSeconds: Double
        var numPaddingLetters: Int
        var words: [GateWord]

        init(from puzzle: GateSpellingConfig) {
            timerSeconds = puzzle.timerSeconds
            numPaddingLetters = puzzle.numPaddingLetters
            words = puzzle.words
        }

        init(
            timerSeconds: Double,
            numPaddingLetters: Int = 6,
            words: [GateWord]
        ) {
            self.timerSeconds = timerSeconds
            self.numPaddingLetters = max(0, numPaddingLetters)
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
    private(set) var targetEntry: GateWord = .fallbackEntry(word: "gate")
    private(set) var letters: [LetterToken] = []
    private(set) var outcome: GateOutcome?
    private(set) var isFrozen = false

    private var lastDisplayedSecond: Int
    private var rng: any RandomNumberGenerator

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

    /// Spelling track for the chosen word (open cue / non-advancing moves).
    var targetSoundTrackID: String { targetEntry.spelling }

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

    /// Advance simulation by `dt`. Returns events for the scene/HUD to react to.
    mutating func tick(dt: Double) -> [GateEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }

        var events: [GateEngineEvent] = []
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

    /// Letters currently inside the staging area, already sorted left→right by center X.
    /// Returns `true` when the puzzle is solved.
    @discardableResult
    mutating func evaluateStaging(orderedLetters: [String]) -> Bool {
        guard isActive, !isFrozen, outcome == nil else { return false }
        let normalized = orderedLetters.map { $0.lowercased() }.joined()
        guard normalized == targetWord else { return false }

        isFrozen = true
        outcome = .won(starsAwarded: targetWord.count)
        return true
    }

    /// Longest staging prefix that matches the target word left-to-right.
    static func connectedPrefix(orderedLetters: [String], targetWord: String) -> String {
        let staged = orderedLetters.map { $0.lowercased() }
        let target = Array(targetWord.lowercased()).map(String.init)
        var prefix = ""
        for index in 0..<min(staged.count, target.count) {
            guard staged[index] == target[index] else { break }
            prefix += staged[index]
        }
        return prefix
    }

    private mutating func pickTargetEntry() -> GateWord {
        let words = config.words
        guard !words.isEmpty else {
            return .fallbackEntry(word: "gate")
        }
        let index = Int.random(in: 0..<words.count, using: &rng)
        return words[index]
    }

    private mutating func buildLetterBag(for word: String) -> [LetterToken] {
        let targetCount = word.count + config.numPaddingLetters
        var bag: [LetterToken] = word.map { character in
            LetterToken(id: UUID(), letter: String(character).lowercased())
        }
        while bag.count < targetCount {
            let index = Int.random(in: 0..<Self.alphabet.count, using: &rng)
            bag.append(LetterToken(id: UUID(), letter: Self.alphabet[index]))
        }
        bag.shuffle(using: &rng)
        return bag
    }
}
