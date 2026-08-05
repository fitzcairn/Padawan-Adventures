import Foundation

/// Pure gate sound-out-word session rules: word pick, one blank-capacitor set per grapheme,
/// and sequential left-to-right placement.
///
/// The engine owns *which* grapheme comes next and *what* is on offer; the scene owns
/// geometry and reports whether a drop landed somewhere legal.
nonisolated struct GateSoundOutWordEngine {
    nonisolated struct Config: Equatable, Sendable {
        var choiceCountMin: Int
        var choiceCountMax: Int
        var words: [GateWord]
        var graphemes: [GateGrapheme]

        init(from puzzle: GateSoundOutWordConfig) {
            self.init(
                choiceCountMin: puzzle.choiceCountMin,
                choiceCountMax: puzzle.choiceCountMax,
                words: puzzle.words,
                graphemes: puzzle.graphemes
            )
        }

        init(
            choiceCountMin: Int = 2,
            choiceCountMax: Int = 4,
            words: [GateWord],
            graphemes: [GateGrapheme]
        ) {
            let low = max(GateSoundOutWordConfig.minChoiceCount, choiceCountMin)
            self.choiceCountMin = low
            self.choiceCountMax = min(
                GateSoundOutWordConfig.maxChoiceCount,
                max(low, choiceCountMax)
            )
            self.words = GateWord.normalized(words)
            self.graphemes = GateGraphemeMatchConfig.normalizedGraphemes(graphemes)
        }
    }

    /// One blank capacitor on offer for a single grapheme of the word.
    nonisolated struct Choice: Equatable, Sendable, Identifiable {
        let id: UUID
        /// Single lowercase grapheme hidden behind the blank face.
        let grapheme: String
        /// Position within its set; drives the subtle tint that tells blanks apart.
        let tintIndex: Int
    }

    nonisolated enum DropOutcome: Equatable, Sendable {
        /// Right grapheme in the right place — the word advances.
        case accepted
        /// Wrong grapheme, or the right grapheme dropped somewhere illegal.
        case rejected
    }

    let config: Config
    private(set) var isActive = false
    private(set) var targetWord = ""
    private(set) var targetEntry: GateWord = .fallbackEntry(word: "gate")
    /// One set per grapheme of the target word, in spelling order.
    private(set) var choiceSets: [[Choice]] = []
    /// Graphemes already placed; doubles as the index of the active set.
    private(set) var placedCount = 0
    private(set) var outcome: MinigameOutcome?

    private var rng: any RandomNumberGenerator

    /// Full-word pronunciation track (opening cue, picture taps, and the win read-back).
    var wordTrackID: String { targetEntry.sound }

    /// Graphemes of the target word, in order.
    var targetGraphemes: [String] { targetWord.map { String($0) } }

    var isSolved: Bool { !targetWord.isEmpty && placedCount >= targetGraphemes.count }

    /// Index of the grapheme the player is working on; `nil` once the word is complete.
    var currentIndex: Int? {
        isSolved || targetWord.isEmpty ? nil : placedCount
    }

    var currentGrapheme: String? {
        currentIndex.flatMap { grapheme(at: $0) }
    }

    /// Capacitors currently on offer; empty once the word is complete.
    var currentChoices: [Choice] {
        guard let index = currentIndex, choiceSets.indices.contains(index) else { return [] }
        return choiceSets[index]
    }

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    mutating func begin() {
        isActive = true
        outcome = nil
        placedCount = 0
        let picked = SpellingMinigameCore.pickTargetEntry(
            from: config.words,
            fallbackWord: "gate",
            using: &rng
        )
        targetEntry = picked
        targetWord = picked.word
        choiceSets = buildChoiceSets(for: targetGraphemes)
    }

    func grapheme(at index: Int) -> String? {
        let graphemes = targetGraphemes
        guard graphemes.indices.contains(index) else { return nil }
        return graphemes[index]
    }

    /// Letter-name track (`"bee"`) used for the flashing prompt at the top of the screen.
    func nameTrackID(for grapheme: String) -> String? {
        entry(for: grapheme).map(\.name).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Letter-sound track (`"buh"`) used when the player taps a blank capacitor.
    func soundTrackID(for grapheme: String) -> String? {
        entry(for: grapheme).map(\.pronunciation).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Resolves a drop. `isPlacementValid` is the scene's geometry verdict: inside the play
    /// area and to the right of the previously placed capacitor.
    @discardableResult
    mutating func drop(choiceID: UUID, isPlacementValid: Bool) -> DropOutcome {
        guard isActive,
              outcome == nil,
              let expected = currentGrapheme,
              let choice = currentChoices.first(where: { $0.id == choiceID }) else {
            return .rejected
        }
        guard choice.grapheme == expected, isPlacementValid else { return .rejected }

        placedCount += 1
        if isSolved {
            outcome = .won(starsAwarded: targetGraphemes.count)
        }
        return .accepted
    }

    private func entry(for grapheme: String) -> GateGrapheme? {
        let key = grapheme.lowercased()
        return config.graphemes.first { $0.grapheme == key }
    }

    /// One shuffled set per grapheme: the answer plus distinct decoys from the catalog.
    private mutating func buildChoiceSets(for graphemes: [String]) -> [[Choice]] {
        let pool = config.graphemes.map(\.grapheme)
        return graphemes.map { answer in
            let requested = Int.random(
                in: config.choiceCountMin...config.choiceCountMax,
                using: &rng
            )
            var decoyPool = pool.filter { $0 != answer }
            decoyPool.shuffle(using: &rng)
            let decoyCount = min(max(requested - 1, 1), decoyPool.count)
            var set = [answer] + decoyPool.prefix(decoyCount)
            set.shuffle(using: &rng)
            return set.enumerated().map { index, grapheme in
                Choice(id: UUID(), grapheme: grapheme, tintIndex: index)
            }
        }
    }
}
