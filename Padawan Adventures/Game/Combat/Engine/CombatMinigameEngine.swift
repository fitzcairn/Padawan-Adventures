import Foundation

nonisolated enum CombatSlashResult: Equatable, Sendable {
    case correct
    case wrong
    case ignored
}

nonisolated enum CombatEngineEvent: Equatable, Sendable {
    case sequenceCue(requiredLetter: String)
    case spawnShot(id: UUID, travelSeconds: Double, visualLetter: String)
    case healthChanged(Int)
    case won
    case lost
}

/// Pure combat session rules (spawn schedule, typed shots, win/lose).
nonisolated struct CombatMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        /// Reference fight length used only to pace spawns; the fight is not time limited.
        var shotPacingSeconds: Double
        /// Derived mean delay between spawns (from pacing window, stars, letter count).
        var meanShotIntervalSeconds: Double
        var shotTravelSeconds: Double
        var starsToWin: Int
        var shotLetters: [String]
        /// Seconds between letter-name cue replays while a sequence is active.
        var graphemeSoundRepeatSeconds: Double
        /// Extra non-matching letters launched alongside the target, per wave.
        var minDecoyCount: Int
        var maxDecoyCount: Int

        /// Assumed fraction of matching shots the player successfully slashes.
        static let defaultAssumedPlayerHitRate: Double = 0.5
        static let defaultGraphemeSoundRepeatSeconds: Double = 3
        /// Multiplier on spawn frequency vs derived baseline (`1.0` = unchanged).
        static let defaultLetterSpawnRate: Double = 1.0
        static let defaultMinDecoyCount = 2
        static let defaultMaxDecoyCount = 4

        init(
            from type: EnemyTypeConfig,
            graphemeSoundRepeatSeconds: Double = defaultGraphemeSoundRepeatSeconds,
            letterSpawnRate: Double = defaultLetterSpawnRate,
            minDecoyCount: Int = defaultMinDecoyCount,
            maxDecoyCount: Int = defaultMaxDecoyCount,
            graphemeCase: CombatGraphemeCase = .upper
        ) {
            let letters = graphemeCase.shotLetterPool(from: type.shotLetters)
            shotPacingSeconds = type.shotPacingSeconds
            shotTravelSeconds = type.shotTravelSeconds
            starsToWin = type.starsToWin
            shotLetters = letters
            self.graphemeSoundRepeatSeconds = max(graphemeSoundRepeatSeconds, 0.05)
            self.minDecoyCount = max(minDecoyCount, 1)
            self.maxDecoyCount = max(maxDecoyCount, self.minDecoyCount)
            let derived = Self.derivedMeanShotInterval(
                shotPacingSeconds: type.shotPacingSeconds,
                shotTravelSeconds: type.shotTravelSeconds,
                starsToWin: type.starsToWin,
                shotLetterCount: letters.count
            )
            let rate = max(letterSpawnRate, 0.05)
            meanShotIntervalSeconds = derived / rate
        }

        init(
            shotPacingSeconds: Double,
            shotTravelSeconds: Double,
            starsToWin: Int,
            shotLetters: [String] = ["A", "B", "C"],
            meanShotIntervalSeconds: Double? = nil,
            graphemeSoundRepeatSeconds: Double = defaultGraphemeSoundRepeatSeconds,
            letterSpawnRate: Double = defaultLetterSpawnRate,
            minDecoyCount: Int = defaultMinDecoyCount,
            maxDecoyCount: Int = defaultMaxDecoyCount
        ) {
            self.shotPacingSeconds = shotPacingSeconds
            self.shotTravelSeconds = shotTravelSeconds
            self.starsToWin = starsToWin
            self.shotLetters = shotLetters
            self.graphemeSoundRepeatSeconds = max(graphemeSoundRepeatSeconds, 0.05)
            self.minDecoyCount = max(minDecoyCount, 1)
            self.maxDecoyCount = max(maxDecoyCount, self.minDecoyCount)
            if let meanShotIntervalSeconds {
                self.meanShotIntervalSeconds = meanShotIntervalSeconds
            } else {
                let derived = Self.derivedMeanShotInterval(
                    shotPacingSeconds: shotPacingSeconds,
                    shotTravelSeconds: shotTravelSeconds,
                    starsToWin: starsToWin,
                    shotLetterCount: shotLetters.count
                )
                let rate = max(letterSpawnRate, 0.05)
                self.meanShotIntervalSeconds = derived / rate
            }
        }

        /// Spawn cadence that yields enough matching shots for `starsToWin` at the assumed hit rate.
        /// Matching visuals occur with probability `1 / shotLetterCount`.
        static func derivedMeanShotInterval(
            shotPacingSeconds: Double,
            shotTravelSeconds: Double,
            starsToWin: Int,
            shotLetterCount: Int,
            assumedPlayerHitRate: Double = defaultAssumedPlayerHitRate
        ) -> Double {
            let letters = max(shotLetterCount, 1)
            let hitRate = min(max(assumedPlayerHitRate, 0.05), 1)
            let matchingShotsNeeded = Int(ceil(Double(max(starsToWin, 1)) / hitRate))
            let totalShotsNeeded = max(matchingShotsNeeded * letters, 1)
            let spawnWindow = max(
                shotPacingSeconds - shotTravelSeconds,
                shotPacingSeconds * 0.4
            )
            return max(spawnWindow / Double(totalShotsNeeded), 0.05)
        }
    }

    nonisolated struct Shot: Equatable, Sendable {
        let id: UUID
        let spawnTime: Double
        let impactTime: Double
        let visualLetter: String
        let requiredLetter: String
    }

    let config: Config
    /// Hearts remaining; starts at `startingHealth` and drops when a matching shot hits.
    private(set) var healthCount: Int
    private let startingHealth: Int
    private(set) var isActive = false
    private(set) var elapsed: Double = 0
    private(set) var combatStars: Int = 0
    private(set) var shots: [UUID: Shot] = [:]
    private(set) var nextSpawnAt: Double = 0
    private(set) var outcome: MinigameOutcome?
    private(set) var isFrozen = false
    private(set) var sequenceRequiredLetter: String = ""

    private var nextCueReplayAt: Double = .infinity
    private var pendingEvents: [CombatEngineEvent] = []
    private var rng: any RandomNumberGenerator

    static let spawnIntervalJitterRange: ClosedRange<Double> = 0.5...1.5
    /// Spawn weight for the currently cued letter vs `1` for each other letter.
    static let cuedLetterSpawnWeight: Double = 2.5

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
        shots = [:]
        outcome = nil
        sequenceRequiredLetter = ""
        nextCueReplayAt = .infinity
        pendingEvents = []
        nextSpawnAt = scheduleNextSpawnDelay()
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    var hasWon: Bool { combatStars >= config.starsToWin }
    var hasLost: Bool { healthCount <= 0 }

    /// Events queued outside `tick` (e.g. cue changes after a correct slash).
    mutating func drainPendingEvents() -> [CombatEngineEvent] {
        let events = pendingEvents
        pendingEvents = []
        return events
    }

    /// Advance simulation by `dt`. Returns events for the scene/HUD to react to.
    mutating func tick(dt: Double) -> [CombatEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }

        var events = drainPendingEvents()
        elapsed += dt

        if !sequenceRequiredLetter.isEmpty, elapsed >= nextCueReplayAt {
            nextCueReplayAt = elapsed + config.graphemeSoundRepeatSeconds
            events.append(.sequenceCue(requiredLetter: sequenceRequiredLetter))
        }

        // Only win / lose / freeze stops new letters.
        while nextSpawnAt <= elapsed,
              outcome == nil,
              !isFrozen {
            if sequenceRequiredLetter.isEmpty {
                beginNewSequence(&events)
            }

            let visual = randomSpawnVisualLetter()
            let required = sequenceRequiredLetter
            let id = UUID()
            let shot = Shot(
                id: id,
                spawnTime: elapsed,
                impactTime: elapsed + config.shotTravelSeconds,
                visualLetter: visual,
                requiredLetter: required
            )
            shots[id] = shot
            events.append(.spawnShot(
                id: id,
                travelSeconds: config.shotTravelSeconds,
                visualLetter: visual
            ))
            nextSpawnAt = elapsed + scheduleNextSpawnDelay()
        }

        if hasLost {
            isFrozen = true
            outcome = .lost
            events.append(.lost)
            return events
        }

        return events
    }

    @discardableResult
    mutating func registerSlashHit(shotID: UUID) -> CombatSlashResult {
        guard isActive, !isFrozen, outcome == nil else { return .ignored }
        guard let shot = shots.removeValue(forKey: shotID) else { return .ignored }

        // Match the live cue — shots already on screen become valid when the cue changes to their letter.
        if shot.visualLetter == sequenceRequiredLetter {
            combatStars += 1
            if hasWon {
                isFrozen = true
                outcome = .won(starsAwarded: config.starsToWin)
            } else {
                // Every correct slash switches the phonetic target to a different letter.
                var cueEvents = pendingEvents
                beginNewSequence(&cueEvents)
                pendingEvents = cueEvents
            }
            return .correct
        }
        // Net progress: wrong slices pull the bar back (display clamps at 0).
        combatStars -= 1
        return .wrong
    }

    /// Removes a shot with no damage (e.g. a miss-path projectile leaving the arena).
    mutating func discardShot(shotID: UUID) {
        shots.removeValue(forKey: shotID)
    }

    /// Removes the shot. Returns `true` when it damages the player (visual matches the live cue).
    /// Matching impacts deduct one heart; at zero hearts the fight is lost.
    @discardableResult
    mutating func registerImpact(shotID: UUID) -> Bool {
        guard let shot = shots.removeValue(forKey: shotID) else { return false }
        guard isActive, !isFrozen, outcome == nil else { return false }
        guard shot.visualLetter == sequenceRequiredLetter else { return false }

        healthCount = max(0, healthCount - 1)
        pendingEvents.append(.healthChanged(healthCount))
        if healthCount <= 0 {
            isFrozen = true
            outcome = .lost
            pendingEvents.append(.lost)
        }
        return true
    }

    /// Whether this shot's visual letter matches the enemy's current cue sound.
    func matchesCurrentCue(shotID: UUID) -> Bool {
        guard let shot = shots[shotID] else { return false }
        return shot.visualLetter == sequenceRequiredLetter
    }

    mutating func scheduleNextSpawnDelay() -> Double {
        let factor = Double.random(in: Self.spawnIntervalJitterRange, using: &rng)
        return config.meanShotIntervalSeconds * factor
    }

    private mutating func beginNewSequence(_ events: inout [CombatEngineEvent]) {
        let required = randomDifferentShotLetter(excluding: sequenceRequiredLetter)
        sequenceRequiredLetter = required
        nextCueReplayAt = elapsed + config.graphemeSoundRepeatSeconds
        events.append(.sequenceCue(requiredLetter: required))
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

    /// Biases toward the live phonetic cue so matching letters appear more often.
    private mutating func randomSpawnVisualLetter() -> String {
        let letters = config.shotLetters
        guard !letters.isEmpty else { return "A" }
        let cued = sequenceRequiredLetter
        guard !cued.isEmpty, letters.contains(cued) else {
            return randomUniformShotLetter()
        }

        var totalWeight = 0.0
        var weights: [Double] = []
        weights.reserveCapacity(letters.count)
        for letter in letters {
            let weight = letter == cued ? Self.cuedLetterSpawnWeight : 1.0
            weights.append(weight)
            totalWeight += weight
        }

        var roll = Double.random(in: 0..<totalWeight, using: &rng)
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll < 0 {
                return letters[index]
            }
        }
        return letters[letters.count - 1]
    }
}
