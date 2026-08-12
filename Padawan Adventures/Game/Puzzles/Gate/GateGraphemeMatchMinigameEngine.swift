import Foundation

nonisolated enum GateGraphemeMatchEngineEvent: Equatable, Sendable {
    case playTargetPronunciation
    case playName(trackID: String)
    case playYay
    case correctMatch(id: UUID)
    case incorrectMatch(id: UUID, pronunciationTrackID: String)
    case won
}

/// Pure gate letter-match puzzle session rules (letter pick, match loop).
nonisolated struct GateGraphemeMatchMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var graphemeCountMin: Int
        var graphemeCountMax: Int
        var graphemeCase: CombatGraphemeCase
        var graphemes: [GateGrapheme]
        var vocabulary: LevelVocabularyPool

        init(from puzzle: GateGraphemeMatchConfig) {
            graphemeCountMin = puzzle.graphemeCountMin
            graphemeCountMax = puzzle.graphemeCountMax
            graphemeCase = puzzle.graphemeCase
            graphemes = puzzle.graphemes
            vocabulary = puzzle.vocabulary
        }

        init(
            graphemeCountMin: Int = 4,
            graphemeCountMax: Int = 8,
            graphemeCase: CombatGraphemeCase = .lower,
            graphemes: [GateGrapheme],
            vocabulary: LevelVocabularyPool? = nil
        ) {
            self.graphemeCountMin = graphemeCountMin
            self.graphemeCountMax = graphemeCountMax
            self.graphemeCase = graphemeCase
            self.graphemes = graphemes.map {
                GateGrapheme(
                    grapheme: $0.grapheme.lowercased(),
                    pronunciation: $0.pronunciation,
                    name: $0.name
                )
            }
            self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(graphemes: self.graphemes)
        }
    }

    nonisolated struct LetterToken: Equatable, Sendable, Identifiable {
        let id: UUID
        /// Display letter, cased per `grapheme_case`.
        let letter: String
        let pronunciationTrackID: String
        let nameTrackID: String
    }

    let config: Config
    private(set) var isActive = false
    private(set) var letters: [LetterToken] = []
    private(set) var matchedIDs: Set<UUID> = []
    private(set) var currentTargetID: UUID?
    private(set) var outcome: MinigameOutcome?
    private(set) var isFrozen = false

    private var rng: any RandomNumberGenerator

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.rng = rng
    }

    var currentTarget: LetterToken? {
        guard let currentTargetID else { return nil }
        return letters.first { $0.id == currentTargetID }
    }

    var targetPronunciationTrackID: String {
        currentTarget?.pronunciationTrackID ?? ""
    }

    mutating func begin() {
        isActive = true
        isFrozen = false
        outcome = nil
        matchedIDs = []
        letters = pickRoundLetters()
        pickNextTarget()
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    /// Handle a tap on a letter tile. Ignores matched / unknown / frozen taps.
    mutating func tapLetter(id: UUID) -> [GateGraphemeMatchEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }
        guard !matchedIDs.contains(id),
              let token = letters.first(where: { $0.id == id }),
              let targetID = currentTargetID else {
            return []
        }

        var events: [GateGraphemeMatchEngineEvent] = [
            .playName(trackID: token.nameTrackID),
        ]

        if token.id == targetID {
            matchedIDs.insert(id)
            events.append(.correctMatch(id: id))
            events.append(.playYay)

            if matchedIDs.count >= letters.count {
                isFrozen = true
                outcome = .won(starsAwarded: letters.count)
                events.append(.won)
            } else {
                pickNextTarget()
                events.append(.playTargetPronunciation)
            }
        } else {
            events.append(
                .incorrectMatch(id: id, pronunciationTrackID: token.pronunciationTrackID)
            )
        }

        return events
    }

    private mutating func pickRoundLetters() -> [LetterToken] {
        let poolSize = max(config.vocabulary.allGraphemes.count, config.graphemes.count)
        guard poolSize > 0 else { return [] }

        let count = Self.sampleLetterCount(
            minimum: config.graphemeCountMin,
            maximum: config.graphemeCountMax,
            poolSize: poolSize,
            rng: &rng
        )
        return config.vocabulary.pickGraphemes(count: count, using: &rng).map { entry in
            LetterToken(
                id: UUID(),
                letter: config.graphemeCase.displayLetter(for: entry.grapheme, rng: &rng),
                pronunciationTrackID: entry.pronunciation,
                nameTrackID: entry.name
            )
        }
    }

    private mutating func pickNextTarget() {
        let unmatched = letters.filter { !matchedIDs.contains($0.id) }
        guard !unmatched.isEmpty else {
            currentTargetID = nil
            return
        }
        let index = Int.random(in: 0..<unmatched.count, using: &rng)
        currentTargetID = unmatched[index].id
    }

    /// Uniformly samples a count in `minimum...maximum`, clamped to `1...poolSize`.
    static func sampleLetterCount(
        minimum: Int,
        maximum: Int,
        poolSize: Int,
        rng: inout some RandomNumberGenerator
    ) -> Int {
        let poolCap = max(1, poolSize)
        let lo = min(max(1, min(minimum, maximum)), poolCap)
        let hi = min(max(lo, max(minimum, maximum)), poolCap)
        return Int.random(in: lo...hi, using: &rng)
    }
}
