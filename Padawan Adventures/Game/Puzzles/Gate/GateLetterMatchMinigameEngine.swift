import Foundation

nonisolated enum GateLetterMatchEngineEvent: Equatable, Sendable {
    case timerTick
    case playTargetPronunciation
    case playName(trackID: String)
    case playYay
    case correctMatch(id: UUID)
    case incorrectMatch(id: UUID, pronunciationTrackID: String)
    case won
    case lost
}

/// Pure gate letter-match puzzle session rules (letter pick, match loop, timer).
nonisolated struct GateLetterMatchMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var timerSeconds: Double
        var letterCountMin: Int
        var letterCountMax: Int
        var letters: [GateLetter]

        init(from puzzle: GateLetterMatchConfig) {
            timerSeconds = puzzle.timerSeconds
            letterCountMin = puzzle.letterCountMin
            letterCountMax = puzzle.letterCountMax
            letters = puzzle.letters
        }

        init(
            timerSeconds: Double,
            letterCountMin: Int = 4,
            letterCountMax: Int = 8,
            letters: [GateLetter]
        ) {
            self.timerSeconds = timerSeconds
            self.letterCountMin = letterCountMin
            self.letterCountMax = letterCountMax
            self.letters = letters.map {
                GateLetter(
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
    private(set) var outcome: GateOutcome?
    private(set) var isFrozen = false

    private var lastDisplayedSecond: Int
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
        letters = pickRoundLetters()
        pickNextTarget()
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    /// Advance simulation by `dt`. Returns events for the scene/HUD to react to.
    /// Timer countdown is HUD-only; the session never ends on expiry.
    mutating func tick(dt: Double) -> [GateLetterMatchEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }

        var events: [GateLetterMatchEngineEvent] = []
        elapsed += dt
        remainingTime = max(0, config.timerSeconds - elapsed)

        let displayedSecond = max(0, Int(ceil(remainingTime - 1e-9)))
        if displayedSecond < lastDisplayedSecond {
            if displayedSecond <= 5, lastDisplayedSecond > 0 {
                events.append(.timerTick)
            }
            lastDisplayedSecond = displayedSecond
        }

        return events
    }

    /// Handle a tap on a letter tile. Ignores matched / unknown / frozen taps.
    mutating func tapLetter(id: UUID) -> [GateLetterMatchEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }
        guard !matchedIDs.contains(id),
              let token = letters.first(where: { $0.id == id }),
              let targetID = currentTargetID else {
            return []
        }

        var events: [GateLetterMatchEngineEvent] = [
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
