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
    private(set) var targetWord: String = ""
    private(set) var targetEntry: GateWord = .fallbackEntry(word: "gate")
    private(set) var letters: [LetterToken] = []
    private(set) var outcome: MinigameOutcome?
    private(set) var isFrozen = false

    private var rng: any RandomNumberGenerator

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)

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
