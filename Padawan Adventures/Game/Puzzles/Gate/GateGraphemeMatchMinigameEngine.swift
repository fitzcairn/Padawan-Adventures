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
        var graphemeSoundRepeatSeconds: Double
        var graphemes: [GateGrapheme]
        var vocabulary: LevelVocabularyPool

        static let defaultGraphemeSoundRepeatSeconds: Double = 3

        init(from puzzle: GateGraphemeMatchConfig) {
            graphemeCountMin = puzzle.graphemeCountMin
            graphemeCountMax = puzzle.graphemeCountMax
            graphemeCase = puzzle.graphemeCase
            graphemeSoundRepeatSeconds = max(puzzle.graphemeSoundRepeatSeconds, 0.05)
            graphemes = puzzle.graphemes
            vocabulary = puzzle.vocabulary
        }

        init(
            graphemeCountMin: Int = 4,
            graphemeCountMax: Int = 8,
            graphemeCase: CombatGraphemeCase = .lower,
            graphemeSoundRepeatSeconds: Double = defaultGraphemeSoundRepeatSeconds,
            graphemes: [GateGrapheme],
            vocabulary: LevelVocabularyPool? = nil
        ) {
            self.graphemeCountMin = graphemeCountMin
            self.graphemeCountMax = graphemeCountMax
            self.graphemeCase = graphemeCase
            self.graphemeSoundRepeatSeconds = max(graphemeSoundRepeatSeconds, 0.05)
            var seen = Set<String>()
            self.graphemes = graphemes.compactMap { entry in
                let id = entry.grapheme.lowercased()
                guard !id.isEmpty, seen.insert(id).inserted else { return nil }
                return GateGrapheme(
                    grapheme: id,
                    pronunciation: entry.pronunciation,
                    name: entry.name
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

    private var elapsed: Double = 0
    private var nextCueReplayAt: Double = .infinity
    private var rng: any RandomNumberGenerator
    private let sampler: LevelVocabularySampler

    init(
        config: Config,
        rng: some RandomNumberGenerator = SystemRandomNumberGenerator(),
        sampler: LevelVocabularySampler? = nil
    ) {
        self.config = config
        self.rng = rng
        self.sampler = sampler ?? LevelVocabularySampler(pool: config.vocabulary)
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
        elapsed = 0
        letters = pickRoundLetters()
        pickNextTarget()
        scheduleCueReplay()
    }

    mutating func end() {
        isActive = false
        isFrozen = true
        nextCueReplayAt = .infinity
    }

    /// Restart the idle prompt clock from the last sound (or player action).
    mutating func noteSoundPlayed() {
        guard isActive, !isFrozen, outcome == nil else { return }
        scheduleCueReplay()
    }

    /// Advance time. When `allowReplay` is false (tap feedback in flight), the idle
    /// prompt is deferred without consuming the due time.
    mutating func tick(dt: Double, allowReplay: Bool = true) -> [GateGraphemeMatchEngineEvent] {
        guard isActive else { return [] }
        elapsed += dt
        guard allowReplay, !isFrozen, outcome == nil, currentTargetID != nil else { return [] }
        guard elapsed >= nextCueReplayAt else { return [] }
        scheduleCueReplay()
        return [.playTargetPronunciation]
    }

    /// Handle a tap on a letter tile. Ignores matched / unknown / frozen taps.
    mutating func tapLetter(id: UUID) -> [GateGraphemeMatchEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }
        guard !matchedIDs.contains(id),
              let token = letters.first(where: { $0.id == id }),
              let targetID = currentTargetID else {
            return []
        }

        noteSoundPlayed()

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

    /// Permutes unmatched letters among their current slots after a wrong tap.
    /// Returns `true` when the unmatched order changed and nodes should slide.
    @discardableResult
    mutating func shuffleUnmatchedLetters() -> Bool {
        let unmatchedIndices = letters.indices.filter { !matchedIDs.contains(letters[$0].id) }
        guard unmatchedIndices.count > 1 else { return false }

        var unmatched = unmatchedIndices.map { letters[$0] }
        let before = unmatched.map(\.id)
        for _ in 0..<8 {
            unmatched.shuffle(using: &rng)
            if unmatched.map(\.id) != before { break }
        }
        guard unmatched.map(\.id) != before else { return false }

        for (slot, token) in zip(unmatchedIndices, unmatched) {
            letters[slot] = token
        }
        return true
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
        let picked = sampler.takeGraphemes(count: count, using: &rng)
        var tokens: [LetterToken] = []
        tokens.reserveCapacity(picked.count)
        for entry in picked {
            tokens.append(
                LetterToken(
                    id: UUID(),
                    letter: config.graphemeCase.displayLetter(for: entry.grapheme, rng: &rng),
                    pronunciationTrackID: entry.pronunciation,
                    nameTrackID: entry.name
                )
            )
        }
        return tokens
    }

    private mutating func scheduleCueReplay() {
        nextCueReplayAt = elapsed + config.graphemeSoundRepeatSeconds
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
