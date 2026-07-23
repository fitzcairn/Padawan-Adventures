import Foundation

nonisolated enum DestructibleWallOutcome: Equatable, Sendable {
    case won(starsAwarded: Int)
    case lost
}

nonisolated enum DestructibleWallEngineEvent: Equatable, Sendable {
    case timerTick
    case playTargetPronunciation
    case playName(trackID: String)
    case playYay
    case correctMatch(id: UUID)
    case incorrectMatch(id: UUID, pronunciationTrackID: String)
    case won
    case lost
}

/// Pure destructible-wall puzzle session rules (letter pick, match loop, timer).
nonisolated struct DestructibleWallMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var timerSeconds: Double
        var letterSoundRepeatSeconds: Double
        var incorrectReplayDelaySeconds: Double
        var letterCountMin: Int
        var letterCountMax: Int
        var letters: [DestructibleWallLetter]

        init(from puzzle: DestructibleWallPuzzleConfig) {
            timerSeconds = puzzle.timerSeconds
            letterSoundRepeatSeconds = puzzle.letterSoundRepeatSeconds
            incorrectReplayDelaySeconds = puzzle.incorrectReplayDelaySeconds
            letterCountMin = puzzle.letterCountMin
            letterCountMax = puzzle.letterCountMax
            letters = puzzle.letters
        }

        init(
            timerSeconds: Double,
            letterSoundRepeatSeconds: Double = 3,
            incorrectReplayDelaySeconds: Double = 1,
            letterCountMin: Int = 2,
            letterCountMax: Int = 4,
            letters: [DestructibleWallLetter]
        ) {
            self.timerSeconds = timerSeconds
            self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
            self.incorrectReplayDelaySeconds = incorrectReplayDelaySeconds
            self.letterCountMin = letterCountMin
            self.letterCountMax = letterCountMax
            self.letters = letters.map {
                DestructibleWallLetter(
                    letter: $0.letter.lowercased(),
                    pronunciation: $0.pronunciation,
                    name: $0.name
                )
            }
        }
    }

    nonisolated struct LetterToken: Equatable, Sendable, Identifiable {
        let id: UUID
        /// Single lowercase letter.
        let letter: String
        let pronunciationTrackID: String
        let nameTrackID: String
    }

    let config: Config
    private(set) var isActive = false
    private(set) var elapsed: Double = 0
    private(set) var remainingTime: Double
    private(set) var letters: [LetterToken] = []
    private(set) var matchedIDs: Set<UUID> = []
    private(set) var currentTargetID: UUID?
    private(set) var outcome: DestructibleWallOutcome?
    private(set) var isFrozen = false

    private var lastDisplayedSecond: Int
    /// Absolute elapsed time when the next target pronunciation should auto-play.
    private var nextTargetSoundElapsed: Double = 0
    private var rng: any RandomNumberGenerator

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.remainingTime = config.timerSeconds
        self.lastDisplayedSecond = Int(ceil(config.timerSeconds))
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
        elapsed = 0
        remainingTime = config.timerSeconds
        outcome = nil
        matchedIDs = []
        lastDisplayedSecond = Int(ceil(config.timerSeconds))
        // Scene plays the first prompt; auto-replay waits for the repeat interval (or mark).
        nextTargetSoundElapsed = config.letterSoundRepeatSeconds
        letters = pickRoundLetters()
        pickNextTarget()
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    var hasLost: Bool { remainingTime <= 0 }

    /// Resets the auto-replay clock after the scene plays the target pronunciation.
    mutating func markTargetSoundPlayed() {
        nextTargetSoundElapsed = elapsed + config.letterSoundRepeatSeconds
    }

    /// Advance simulation by `dt`. Returns events for the scene/HUD to react to.
    mutating func tick(dt: Double) -> [DestructibleWallEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }

        var events: [DestructibleWallEngineEvent] = []
        elapsed += dt
        remainingTime = max(0, config.timerSeconds - elapsed)

        let displayedSecond = max(0, Int(ceil(remainingTime - 1e-9)))
        if displayedSecond < lastDisplayedSecond {
            if displayedSecond <= 5, lastDisplayedSecond > 0 {
                events.append(.timerTick)
            }
            lastDisplayedSecond = displayedSecond
        }

        if elapsed >= nextTargetSoundElapsed {
            nextTargetSoundElapsed = elapsed + config.letterSoundRepeatSeconds
            events.append(.playTargetPronunciation)
        }

        if hasLost {
            isFrozen = true
            outcome = .lost
            events.append(.lost)
        }

        return events
    }

    /// Handle a tap on a letter tile. Ignores matched / unknown / frozen taps.
    mutating func tapLetter(id: UUID) -> [DestructibleWallEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }
        guard !matchedIDs.contains(id),
              let token = letters.first(where: { $0.id == id }),
              let targetID = currentTargetID else {
            return []
        }

        var events: [DestructibleWallEngineEvent] = [
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
                // Prompt the next target promptly after a correct match.
                nextTargetSoundElapsed = elapsed
            }
        } else {
            events.append(
                .incorrectMatch(id: id, pronunciationTrackID: token.pronunciationTrackID)
            )
            nextTargetSoundElapsed = elapsed + config.incorrectReplayDelaySeconds
        }

        return events
    }

    private mutating func pickRoundLetters() -> [LetterToken] {
        let pool = config.letters
        guard !pool.isEmpty else { return [] }

        let count = Self.sampleLetterCount(
            minimum: config.letterCountMin,
            maximum: config.letterCountMax,
            poolSize: pool.count,
            rng: &rng
        )
        var shuffled = pool
        shuffled.shuffle(using: &rng)
        return shuffled.prefix(count).map { entry in
            LetterToken(
                id: UUID(),
                letter: entry.letter.lowercased(),
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
