import Foundation

/// The three tap targets around the player, ordered left to right on screen.
/// Raw values index into `CombatDeflectConfig.letters`.
nonisolated enum CombatDeflectRing: Int, CaseIterable, Equatable, Sendable {
    case northwest = 0
    case up = 1
    case northeast = 2
}

nonisolated enum CombatDeflectTapResult: Equatable, Sendable {
    case correct(CombatDeflectRing)
    case wrong(CombatDeflectRing)
    /// No live orb, the orb is already resolved, or the session is over.
    case ignored
}

nonisolated enum CombatDeflectEvent: Equatable, Sendable {
    case throwOrb(id: UUID, letter: String, ring: CombatDeflectRing, travelSeconds: Double)
    /// Phonetic letter-name track; playing it ducks music + loops automatically.
    case speakLetter(trackID: String)
    case monsterHealthChanged(Int)
    case playerHealthChanged(Int)
    case won(starsAwarded: Int)
    case lost
}

/// Pure rules for the deflect arena: one orb at a time, tap the ring whose letter
/// matches it, deflect it back to drain monster HP.
///
/// The scene owns every animation timing decision and drives the engine with explicit
/// calls, so there is no internal clock and no `tick`.
nonisolated struct CombatDeflectMinigameEngine {
    nonisolated struct Config: Equatable, Sendable {
        /// Ring letters left to right (northwest, up, northeast).
        var letters: [GateLetter]
        var monsterHP: Int
        var orbTravelSeconds: Double

        init(letters: [GateLetter], monsterHP: Int, orbTravelSeconds: Double) {
            self.letters = letters
            self.monsterHP = max(monsterHP, 1)
            self.orbTravelSeconds = max(orbTravelSeconds, 0.2)
        }

        init(from deflect: CombatDeflectConfig) {
            self.init(
                letters: deflect.letters,
                monsterHP: deflect.monsterHP,
                orbTravelSeconds: deflect.orbTravelSeconds
            )
        }
    }

    nonisolated struct Orb: Equatable, Sendable {
        let id: UUID
        let letter: String
        /// The ring that deflects this orb.
        let ring: CombatDeflectRing
        /// True once the player answered; the scene is animating the consequence.
        var isResolved: Bool
    }

    let config: Config
    private(set) var monsterHP: Int
    private(set) var healthCount: Int
    private(set) var activeOrb: Orb?
    private(set) var outcome: CombatOutcome?
    private(set) var isActive = false

    private let startingHealth: Int
    private var rng: any RandomNumberGenerator

    init(
        config: Config,
        startingHealth: Int = 3,
        rng: some RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.config = config
        self.startingHealth = max(startingHealth, 0)
        self.healthCount = self.startingHealth
        self.monsterHP = config.monsterHP
        self.rng = rng
    }

    var hasWon: Bool { monsterHP <= 0 }
    var hasLost: Bool { healthCount <= 0 }

    mutating func begin() {
        isActive = true
        outcome = nil
        healthCount = startingHealth
        monsterHP = config.monsterHP
        activeOrb = nil
    }

    mutating func end() {
        isActive = false
    }

    /// Throws the next orb. Returns no events when inactive, finished, or an orb is live.
    mutating func throwNextOrb() -> [CombatDeflectEvent] {
        guard isActive, outcome == nil, activeOrb == nil, !config.letters.isEmpty else {
            return []
        }
        let index = Int.random(in: 0..<config.letters.count, using: &rng)
        guard let ring = CombatDeflectRing(rawValue: index) else { return [] }
        let entry = config.letters[index]
        let orb = Orb(id: UUID(), letter: entry.letter, ring: ring, isResolved: false)
        activeOrb = orb
        return [
            .throwOrb(
                id: orb.id,
                letter: orb.letter,
                ring: ring,
                travelSeconds: config.orbTravelSeconds
            ),
            .speakLetter(trackID: entry.name),
        ]
    }

    /// Player tapped `ring`. Marks the orb resolved so a second tap cannot double-fire.
    /// The scene then animates either the deflect or the hit and calls the matching
    /// `register…` method when the animation lands.
    mutating func registerTap(ring: CombatDeflectRing) -> CombatDeflectTapResult {
        guard isActive, outcome == nil, var orb = activeOrb, !orb.isResolved else {
            return .ignored
        }
        orb.isResolved = true
        activeOrb = orb
        return orb.ring == ring ? .correct(orb.ring) : .wrong(ring)
    }

    /// The deflected orb reached the monster: -1 monster HP, maybe win.
    mutating func registerOrbReachedMonster() -> [CombatDeflectEvent] {
        guard isActive, outcome == nil, activeOrb != nil else { return [] }
        activeOrb = nil
        monsterHP = max(0, monsterHP - 1)
        var events: [CombatDeflectEvent] = [.monsterHealthChanged(monsterHP)]
        if hasWon {
            outcome = .won(starsAwarded: config.monsterHP)
            events.append(.won(starsAwarded: config.monsterHP))
        }
        return events
    }

    /// The orb hit the player (wrong tap, or it arrived untapped): -1 heart, maybe lose.
    mutating func registerOrbHitPlayer() -> [CombatDeflectEvent] {
        guard isActive, outcome == nil, activeOrb != nil else { return [] }
        activeOrb = nil
        healthCount = max(0, healthCount - 1)
        var events: [CombatDeflectEvent] = [.playerHealthChanged(healthCount)]
        if hasLost {
            outcome = .lost
            events.append(.lost)
        }
        return events
    }
}
