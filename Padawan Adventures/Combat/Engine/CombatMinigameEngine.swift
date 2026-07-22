import Foundation

nonisolated enum CombatOutcome: Equatable, Sendable {
    case won(starsAwarded: Int)
    case lost
}

nonisolated enum CombatSlashResult: Equatable, Sendable {
    case correct
    case wrong
    case ignored
}

nonisolated enum CombatEngineEvent: Equatable, Sendable {
    case sequenceCue(requiredLetter: String)
    case spawnShot(id: UUID, travelSeconds: Double, visualLetter: String)
    case timerTick
    case won
    case lost
}

/// Pure combat session rules (timer, spawn schedule, typed shots, win/lose).
nonisolated struct CombatMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var combatTimerSeconds: Double
        /// Derived mean delay between spawns (from timer, stars, letter count).
        var meanShotIntervalSeconds: Double
        var shotTravelSeconds: Double
        var starsToWin: Int
        var shotLetters: [String]

        /// Assumed fraction of matching shots the player successfully slashes.
        static let defaultAssumedPlayerHitRate: Double = 0.5

        init(from type: EnemyTypeConfig) {
            let letters = type.shotLetters
            combatTimerSeconds = type.combatTimerSeconds
            shotTravelSeconds = type.shotTravelSeconds
            starsToWin = type.starsToWin
            shotLetters = letters
            meanShotIntervalSeconds = Self.derivedMeanShotInterval(
                combatTimerSeconds: type.combatTimerSeconds,
                shotTravelSeconds: type.shotTravelSeconds,
                starsToWin: type.starsToWin,
                shotLetterCount: letters.count
            )
        }

        init(
            combatTimerSeconds: Double,
            shotTravelSeconds: Double,
            starsToWin: Int,
            shotLetters: [String] = ["A", "B", "C"],
            meanShotIntervalSeconds: Double? = nil
        ) {
            self.combatTimerSeconds = combatTimerSeconds
            self.shotTravelSeconds = shotTravelSeconds
            self.starsToWin = starsToWin
            self.shotLetters = shotLetters
            self.meanShotIntervalSeconds = meanShotIntervalSeconds ?? Self.derivedMeanShotInterval(
                combatTimerSeconds: combatTimerSeconds,
                shotTravelSeconds: shotTravelSeconds,
                starsToWin: starsToWin,
                shotLetterCount: shotLetters.count
            )
        }

        /// Spawn cadence that yields enough matching shots for `starsToWin` at the assumed hit rate.
        /// Matching visuals occur with probability `1 / shotLetterCount`.
        static func derivedMeanShotInterval(
            combatTimerSeconds: Double,
            shotTravelSeconds: Double,
            starsToWin: Int,
            shotLetterCount: Int,
            assumedPlayerHitRate: Double = defaultAssumedPlayerHitRate
        ) -> Double {
            let letters = max(shotLetterCount, 1)
            let hitRate = min(max(assumedPlayerHitRate, 0.05), 1)
            let matchingShotsNeeded = Int(ceil(Double(max(starsToWin, 1)) / hitRate))
            let totalShotsNeeded = max(matchingShotsNeeded * letters, 1)
            // Leave travel time so the last spawned shot is still slashable before the timer ends.
            let spawnWindow = max(
                combatTimerSeconds - shotTravelSeconds,
                combatTimerSeconds * 0.4
            )
            return max(spawnWindow / Double(totalShotsNeeded), 0.05)
        }

        /// Latest elapsed time at which a new shot may still spawn.
        var spawnWindowEnd: Double {
            max(combatTimerSeconds - shotTravelSeconds, combatTimerSeconds * 0.4)
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
    private(set) var isActive = false
    private(set) var elapsed: Double = 0
    private(set) var remainingTime: Double
    private(set) var combatStars: Int = 0
    private(set) var shots: [UUID: Shot] = [:]
    private(set) var nextSpawnAt: Double = 0
    private(set) var outcome: CombatOutcome?
    private(set) var isFrozen = false
    private(set) var sequenceRequiredLetter: String = ""
    /// Correct slashes still needed before the cue sound / required letter changes.
    private(set) var correctSlashesRemainingInSequence: Int = 0

    private var lastDisplayedSecond: Int
    private var pendingEvents: [CombatEngineEvent] = []
    private var rng: any RandomNumberGenerator

    /// Mean number of correct slashes required before changing the cue sound.
    static let correctSlashesPerCueMean: Double = 3
    static let spawnIntervalJitterRange: ClosedRange<Double> = 0.5...1.5
    static let correctSlashesJitterRange: ClosedRange<Double> = 0.5...1.5

    init(config: Config, rng: some RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.config = config
        self.remainingTime = config.combatTimerSeconds
        self.lastDisplayedSecond = Int(ceil(config.combatTimerSeconds))
        self.rng = rng
    }

    mutating func begin() {
        isActive = true
        isFrozen = false
        elapsed = 0
        remainingTime = config.combatTimerSeconds
        combatStars = 0
        shots = [:]
        outcome = nil
        sequenceRequiredLetter = ""
        correctSlashesRemainingInSequence = 0
        pendingEvents = []
        lastDisplayedSecond = Int(ceil(config.combatTimerSeconds))
        nextSpawnAt = scheduleNextSpawnDelay()
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    var hasWon: Bool { combatStars >= config.starsToWin }
    var hasLost: Bool { remainingTime <= 0 }

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
        remainingTime = max(0, config.combatTimerSeconds - elapsed)

        let displayedSecond = max(0, Int(ceil(remainingTime - 1e-9)))
        if displayedSecond < lastDisplayedSecond {
            if displayedSecond <= 5, lastDisplayedSecond > 0 {
                events.append(.timerTick)
            }
            lastDisplayedSecond = displayedSecond
        }

        while nextSpawnAt <= elapsed,
              elapsed <= config.spawnWindowEnd,
              outcome == nil,
              !isFrozen {
            if correctSlashesRemainingInSequence <= 0 {
                beginNewSequence(&events)
            }

            let visual = randomShotLetter()
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
            if correctSlashesRemainingInSequence > 0 {
                correctSlashesRemainingInSequence -= 1
            }
            if hasWon {
                isFrozen = true
                outcome = .won(starsAwarded: config.starsToWin)
            } else if correctSlashesRemainingInSequence <= 0 {
                var cueEvents = pendingEvents
                beginNewSequence(&cueEvents)
                pendingEvents = cueEvents
            }
            return .correct
        }
        return .wrong
    }

    /// Removes the shot. Returns `true` when it should damage the player (visual matches the live cue).
    @discardableResult
    mutating func registerImpact(shotID: UUID) -> Bool {
        guard let shot = shots.removeValue(forKey: shotID) else { return false }
        return shot.visualLetter == sequenceRequiredLetter
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

    mutating func scheduleCorrectSlashesRequired() -> Int {
        let raw = Self.correctSlashesPerCueMean * Double.random(in: Self.correctSlashesJitterRange, using: &rng)
        return max(1, Int(raw.rounded()))
    }

    private mutating func beginNewSequence(_ events: inout [CombatEngineEvent]) {
        let required = randomShotLetter()
        sequenceRequiredLetter = required
        correctSlashesRemainingInSequence = scheduleCorrectSlashesRequired()
        events.append(.sequenceCue(requiredLetter: required))
    }

    private mutating func randomShotLetter() -> String {
        let letters = config.shotLetters
        guard !letters.isEmpty else { return "A" }
        let index = Int.random(in: 0..<letters.count, using: &rng)
        return letters[index]
    }
}
