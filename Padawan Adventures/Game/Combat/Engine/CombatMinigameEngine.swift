import Foundation

nonisolated enum CombatSlashResult: Equatable, Sendable {
    case correct
    case wrong
    case ignored
}

/// One projectile in a wave. `laneIndex` is a pre-shuffled fan slot the scene uses to
/// spread paths apart; `speedJitter` is this sprite's +/-10% speed factor.
nonisolated struct CombatWaveShot: Equatable, Sendable {
    let id: UUID
    let letter: String
    let isTarget: Bool
    let speedJitter: Double
    let laneIndex: Int
}

nonisolated enum CombatWavePhase: Equatable, Sendable {
    /// Waiting out the gap before the next wave launches.
    case pending
    /// Sprites in flight, awaiting the player's slash.
    case active
    /// Outcome decided; the scene is playing the reflect / sweep-off or the charge.
    case resolving
}

nonisolated enum CombatWaveFailure: Equatable, Sendable {
    case impact(UUID)
}

nonisolated enum CombatEngineEvent: Equatable, Sendable {
    case sequenceCue(requiredLetter: String)
    case spawnWave(targetLetter: String, shots: [CombatWaveShot])
    case healthChanged(Int)
    case won
    case lost
}

/// Pure combat session rules (wave schedule, typed shots, win/lose).
nonisolated struct CombatMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        /// Reference flight time for a straight enemy-to-player path. The scene turns this
        /// into a constant speed, so longer fanned paths simply take proportionally longer.
        var shotTravelSeconds: Double
        var starsToWin: Int
        var shotLetters: [String]
        /// Seconds between pronunciation cue replays while a wave is active.
        var graphemeSoundRepeatSeconds: Double
        /// Extra non-matching letters launched alongside the target, per wave.
        var minDecoyCount: Int
        var maxDecoyCount: Int

        static let defaultGraphemeSoundRepeatSeconds: Double = 3
        static let defaultMinDecoyCount = 2
        static let defaultMaxDecoyCount = 4

        init(
            from type: EnemyTypeConfig,
            graphemeSoundRepeatSeconds: Double = defaultGraphemeSoundRepeatSeconds,
            minDecoyCount: Int = defaultMinDecoyCount,
            maxDecoyCount: Int = defaultMaxDecoyCount,
            graphemeCase: CombatGraphemeCase = .upper
        ) {
            let letters = graphemeCase.shotLetterPool(from: type.shotLetters)
            shotTravelSeconds = type.shotTravelSeconds
            starsToWin = type.starsToWin
            shotLetters = letters
            self.graphemeSoundRepeatSeconds = max(graphemeSoundRepeatSeconds, 0.05)
            self.minDecoyCount = max(minDecoyCount, 1)
            self.maxDecoyCount = max(maxDecoyCount, self.minDecoyCount)
        }

        init(
            shotTravelSeconds: Double,
            starsToWin: Int,
            shotLetters: [String] = ["A", "B", "C"],
            graphemeSoundRepeatSeconds: Double = defaultGraphemeSoundRepeatSeconds,
            minDecoyCount: Int = defaultMinDecoyCount,
            maxDecoyCount: Int = defaultMaxDecoyCount
        ) {
            self.shotTravelSeconds = shotTravelSeconds
            self.starsToWin = starsToWin
            self.shotLetters = shotLetters
            self.graphemeSoundRepeatSeconds = max(graphemeSoundRepeatSeconds, 0.05)
            self.minDecoyCount = max(minDecoyCount, 1)
            self.maxDecoyCount = max(maxDecoyCount, self.minDecoyCount)
        }
    }

    let config: Config
    /// Hearts remaining; starts at `startingHealth` and drops when a wave fails.
    private(set) var healthCount: Int
    private let startingHealth: Int
    private(set) var isActive = false
    private(set) var elapsed: Double = 0
    private(set) var combatStars: Int = 0
    private(set) var outcome: MinigameOutcome?
    private(set) var isFrozen = false
    /// The letter currently being spoken; fixed for the whole wave.
    private(set) var sequenceRequiredLetter: String = ""
    private(set) var wavePhase: CombatWavePhase = .pending
    private(set) var waveShots: [UUID: CombatWaveShot] = [:]
    private(set) var waveIndex = 0

    private var nextWaveAt: Double = 0
    private var nextCueReplayAt: Double = .infinity
    private var pendingEvents: [CombatEngineEvent] = []
    private var rng: any RandomNumberGenerator

    static let speedJitterRange: ClosedRange<Double> = 0.9...1.1
    static let firstWaveDelaySeconds: Double = 0.4
    static let waveGapSeconds: Double = 0.5

    /// Slashes and impacts only register while a wave is live and undecided.
    var acceptsInput: Bool {
        isActive && !isFrozen && outcome == nil && wavePhase == .active
    }

    func isTargetShot(_ id: UUID) -> Bool { waveShots[id]?.isTarget == true }

    init(
        config: Config,
        startingHealth: Int = 3,
        rng: some RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.config = config
        self.startingHealth = max(startingHealth, 0)
        self.healthCount = self.startingHealth
        self.rng = rng
    }

    mutating func begin() {
        isActive = true
        isFrozen = false
        elapsed = 0
        healthCount = startingHealth
        combatStars = 0
        outcome = nil
        sequenceRequiredLetter = ""
        wavePhase = .pending
        waveShots = [:]
        waveIndex = 0
        nextCueReplayAt = .infinity
        pendingEvents = []
        nextWaveAt = Self.firstWaveDelaySeconds
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    var hasWon: Bool { combatStars >= config.starsToWin }
    var hasLost: Bool { healthCount <= 0 }

    /// Events queued outside `tick` (e.g. health changes after a failed wave).
    mutating func drainPendingEvents() -> [CombatEngineEvent] {
        let events = pendingEvents
        pendingEvents = []
        return events
    }

    /// Advance simulation by `dt`. Returns events for the scene/HUD to react to.
    mutating func tick(dt: Double) -> [CombatEngineEvent] {
        guard isActive, outcome == nil else { return [] }
        var events = drainPendingEvents()
        elapsed += dt

        switch wavePhase {
        case .pending:
            if elapsed >= nextWaveAt { beginWave(&events) }
        case .active:
            if !sequenceRequiredLetter.isEmpty, elapsed >= nextCueReplayAt {
                nextCueReplayAt = elapsed + config.graphemeSoundRepeatSeconds
                events.append(.sequenceCue(requiredLetter: sequenceRequiredLetter))
            }
        case .resolving:
            break // Waiting on the scene to call finishWaveResolution().
        }
        return events
    }

    private mutating func beginWave(_ events: inout [CombatEngineEvent]) {
        let target = randomDifferentShotLetter(excluding: sequenceRequiredLetter)
        sequenceRequiredLetter = target

        // Decoys repeat freely but never match the target, so a 3-letter pool still fills 4 slots.
        let decoyPool = config.shotLetters.filter { $0 != target }
        let requested = Int.random(in: config.minDecoyCount...config.maxDecoyCount, using: &rng)
        let decoyCount = decoyPool.isEmpty ? 0 : requested

        var letters: [(letter: String, isTarget: Bool)] = [(target, true)]
        for _ in 0..<decoyCount {
            letters.append((decoyPool[Int.random(in: 0..<decoyPool.count, using: &rng)], false))
        }

        // Fisher-Yates so the target's fan slot (and therefore screen position) is unpredictable.
        var lanes = Array(0..<letters.count)
        if lanes.count > 1 {
            for i in stride(from: lanes.count - 1, to: 0, by: -1) {
                lanes.swapAt(i, Int.random(in: 0...i, using: &rng))
            }
        }

        let shots = letters.enumerated().map { offset, entry in
            CombatWaveShot(
                id: UUID(),
                letter: entry.letter,
                isTarget: entry.isTarget,
                speedJitter: Double.random(in: Self.speedJitterRange, using: &rng),
                laneIndex: lanes[offset]
            )
        }

        waveShots = Dictionary(uniqueKeysWithValues: shots.map { ($0.id, $0) })
        wavePhase = .active
        waveIndex += 1
        nextCueReplayAt = elapsed + config.graphemeSoundRepeatSeconds
        events.append(.sequenceCue(requiredLetter: target))
        events.append(.spawnWave(targetLetter: target, shots: shots))
    }

    @discardableResult
    mutating func registerSlashHit(shotID: UUID) -> CombatSlashResult {
        guard acceptsInput, let shot = waveShots[shotID] else { return .ignored }
        guard shot.isTarget else {
            // Soft miss: drop the decoy so it cannot be hit again, but keep the wave live
            // so the player can still slash the cued letter before anything lands.
            waveShots[shotID] = nil
            return .wrong
        }
        combatStars += 1
        wavePhase = .resolving
        if combatStars >= config.starsToWin {
            // Decided now so no further waves spawn; `.won` is emitted once the scene
            // has reflected the target and swept the decoys off screen.
            outcome = .won(starsAwarded: config.starsToWin)
            isFrozen = true
        }
        return .correct
    }

    /// First sprite of a live wave to reach the player. Returns true when this call is the
    /// one that failed the wave, so the scene knows to start the charge choreography.
    @discardableResult
    mutating func registerWaveImpact(shotID: UUID) -> Bool {
        guard acceptsInput, waveShots[shotID] != nil else { return false }
        failWave()
        return true
    }

    /// A letter reaching the player costs exactly one heart for the whole wave.
    private mutating func failWave() {
        guard wavePhase == .active else { return }
        wavePhase = .resolving
        healthCount = max(0, healthCount - 1)
        pendingEvents.append(.healthChanged(healthCount))
        if healthCount <= 0 {
            outcome = .lost
            isFrozen = true
        }
    }

    /// Called by the scene once the reflect / sweep-off / charge choreography has played out.
    mutating func finishWaveResolution() -> [CombatEngineEvent] {
        guard wavePhase == .resolving else { return [] }
        waveShots = [:]
        wavePhase = .pending
        var events = drainPendingEvents()
        if let outcome {
            events.append(outcome == .lost ? .lost : .won)
            return events
        }
        nextWaveAt = elapsed + Self.waveGapSeconds
        return events
    }

    private mutating func randomUniformShotLetter() -> String {
        let letters = config.shotLetters
        guard !letters.isEmpty else { return "A" }
        let index = Int.random(in: 0..<letters.count, using: &rng)
        return letters[index]
    }

    /// Picks uniformly from the alphabet, excluding `current` when other letters exist.
    private mutating func randomDifferentShotLetter(excluding current: String) -> String {
        let letters = config.shotLetters
        let others = letters.filter { $0 != current }
        guard !others.isEmpty else { return randomUniformShotLetter() }
        let index = Int.random(in: 0..<others.count, using: &rng)
        return others[index]
    }
}
