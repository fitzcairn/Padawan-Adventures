import Foundation

/// Pure gate puzzle session rules (word pick, letter bag, staging win check).
nonisolated struct GateMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var numPaddingLetters: Int
        var words: [GateWord]

        init(from puzzle: GateSpellingConfig) {
            numPaddingLetters = puzzle.numPaddingLetters
            words = puzzle.words
        }

        init(
            numPaddingLetters: Int = 6,
            words: [GateWord]
        ) {
            self.numPaddingLetters = max(0, numPaddingLetters)
            self.words = words.map {
                GateWord(
                    word: $0.word.lowercased(),
                    image: $0.image,
                    sfx: $0.sfx,
                    progressive: $0.progressive
                )
            }
        }
    }

    typealias LetterToken = SpellingMinigameCore.LetterToken

    let config: Config
    private(set) var isActive = false
    private(set) var targetWord: String = ""
    private(set) var targetEntry: GateWord = .fallbackEntry(word: "gate")
    private(set) var letters: [LetterToken] = []
    private(set) var outcome: MinigameOutcome?
    private(set) var isFrozen = false

    private var rng: any RandomNumberGenerator

    /// Spelling track for the chosen word (open cue / non-advancing moves).
    var targetSoundTrackID: String { targetEntry.spelling }

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    mutating func begin() {
        isActive = true
        isFrozen = false
        outcome = nil
        let picked = pickTargetEntry()
        targetEntry = picked
        targetWord = picked.word
        letters = buildLetterBag(for: targetWord)
    }

    mutating func end() {
        isActive = false
        isFrozen = true
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
        SpellingMinigameCore.pickTargetEntry(from: config.words, fallbackWord: "gate", using: &rng)
    }

    private mutating func buildLetterBag(for word: String) -> [LetterToken] {
        SpellingMinigameCore.buildLetterBag(
            for: word,
            numPaddingLetters: config.numPaddingLetters,
            using: &rng
        )
    }
}
