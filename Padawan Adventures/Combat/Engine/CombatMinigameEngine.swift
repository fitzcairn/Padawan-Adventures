import Foundation

nonisolated enum CombatOutcome: Equatable, Sendable {
    case won(starsAwarded: Int)
    case lost
}

nonisolated enum CombatEngineEvent: Equatable, Sendable {
    case spawnShot(id: UUID, travelSeconds: Double)
    case timerTick
    case won
    case lost
}

/// Pure combat session rules (timer, spawn schedule, stars, win/lose).
nonisolated struct CombatMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        var combatTimerSeconds: Double
        var shotIntervalSeconds: Double
        var shotTravelSeconds: Double
        var starsToWin: Int

        init(from type: EnemyTypeConfig) {
            combatTimerSeconds = type.combatTimerSeconds
            shotIntervalSeconds = type.shotIntervalSeconds
            shotTravelSeconds = type.shotTravelSeconds
            starsToWin = type.starsToWin
        }

        init(
            combatTimerSeconds: Double,
            shotIntervalSeconds: Double,
            shotTravelSeconds: Double,
            starsToWin: Int
        ) {
            self.combatTimerSeconds = combatTimerSeconds
            self.shotIntervalSeconds = shotIntervalSeconds
            self.shotTravelSeconds = shotTravelSeconds
            self.starsToWin = starsToWin
        }
    }

    nonisolated struct Shot: Equatable, Sendable {
        let id: UUID
        let spawnTime: Double
        let impactTime: Double
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

    private var lastDisplayedSecond: Int
    private var rng: any RandomNumberGenerator

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
        lastDisplayedSecond = Int(ceil(config.combatTimerSeconds))
        nextSpawnAt = scheduleNextSpawnDelay()
    }

    mutating func end() {
        isActive = false
        isFrozen = true
    }

    var hasWon: Bool { combatStars >= config.starsToWin }
    var hasLost: Bool { remainingTime <= 0 }

    /// Advance simulation by `dt`. Returns events for the scene/HUD to react to.
    mutating func tick(dt: Double) -> [CombatEngineEvent] {
        guard isActive, !isFrozen, outcome == nil else { return [] }

        var events: [CombatEngineEvent] = []
        elapsed += dt
        remainingTime = max(0, config.combatTimerSeconds - elapsed)

        let displayedSecond = max(0, Int(ceil(remainingTime - 1e-9)))
        if displayedSecond < lastDisplayedSecond {
            if displayedSecond <= 5, lastDisplayedSecond > 0 {
                events.append(.timerTick)
            }
            lastDisplayedSecond = displayedSecond
        }

        while nextSpawnAt <= elapsed, outcome == nil, !isFrozen {
            let id = UUID()
            let shot = Shot(
                id: id,
                spawnTime: elapsed,
                impactTime: elapsed + config.shotTravelSeconds
            )
            shots[id] = shot
            events.append(.spawnShot(id: id, travelSeconds: config.shotTravelSeconds))
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

    /// Register a successful slash on a live shot. Returns true if the shot was removed.
    @discardableResult
    mutating func registerSlashHit(shotID: UUID) -> Bool {
        guard isActive, !isFrozen, outcome == nil else { return false }
        guard shots.removeValue(forKey: shotID) != nil else { return false }
        combatStars += 1
        if hasWon {
            isFrozen = true
            outcome = .won(starsAwarded: config.starsToWin)
        }
        return true
    }

    /// Remove a shot that impacted the player (no star).
    @discardableResult
    mutating func registerImpact(shotID: UUID) -> Bool {
        guard shots.removeValue(forKey: shotID) != nil else { return false }
        return true
    }

    /// Delay multiplier range around the configured average spawn interval.
    static let spawnIntervalJitterRange: ClosedRange<Double> = 0.5...1.5

    mutating func scheduleNextSpawnDelay() -> Double {
        let factor = Double.random(in: Self.spawnIntervalJitterRange, using: &rng)
        return config.shotIntervalSeconds * factor
    }
}
