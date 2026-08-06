import Foundation

/// A tap target around the player. `index` is an index into `CombatDeflectConfig.letters`,
/// ordered left to right on screen.
nonisolated struct CombatDeflectRing: Hashable, Equatable, Comparable, Sendable {
    let index: Int

    var rawValue: Int { index }

    init(_ index: Int) {
        self.index = index
    }

    init?(rawValue: Int) {
        guard rawValue >= 0 else { return nil }
        self.index = rawValue
    }

    static func < (lhs: CombatDeflectRing, rhs: CombatDeflectRing) -> Bool {
        lhs.index < rhs.index
    }

    /// Rings `0..<count`, left to right.
    static func all(count: Int) -> [CombatDeflectRing] {
        (0..<max(count, 0)).map(CombatDeflectRing.init)
    }
}

nonisolated enum CombatDeflectTapResult: Equatable, Sendable {
    case correct(CombatDeflectRing)
    case wrong(CombatDeflectRing)
    /// No live orb, the orb is already resolved, or the session is over.
    case ignored
}

nonisolated enum CombatDeflectEvent: Equatable, Sendable {
    /// `letter` is the ring that deflects this orb; `word` / `imageName` drive the thrown sprite + SFX.
    case throwOrb(
        id: UUID,
        letter: String,
        word: String,
        imageName: String?,
        ring: CombatDeflectRing,
        travelSeconds: Double
    )
    /// Full-word pronunciation track (`sfx_word_*`); ducks music + loops automatically.
    case speakWord(trackID: String)
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
        /// Ring letters left to right (2…6 entries).
        var graphemes: [GateGrapheme]
        /// Vocabulary used to pick a thrown word for each letter (typically the full catalog).
        var words: [GateWord]
        var monsterHP: Int
        var orbTravelSeconds: Double
        var letterPosition: GateWordPlugLetterPosition

        var ringCount: Int { graphemes.count }

        init(
            graphemes: [GateGrapheme],
            words: [GateWord] = WordCatalog.fallback.words,
            monsterHP: Int,
            orbTravelSeconds: Double,
            letterPosition: GateWordPlugLetterPosition = .starting
        ) {
            self.graphemes = graphemes
            self.words = words
            self.monsterHP = max(monsterHP, 1)
            self.orbTravelSeconds = max(orbTravelSeconds, 0.2)
            self.letterPosition = letterPosition
        }

        init(from deflect: CombatDeflectConfig) {
            self.init(
                graphemes: deflect.graphemes,
                words: deflect.words.isEmpty ? WordCatalog.fallback.words : deflect.words,
                monsterHP: deflect.monsterHP,
                orbTravelSeconds: deflect.orbTravelSeconds,
                letterPosition: deflect.letterPosition
            )
        }

        /// Imaged vocabulary entries whose first (or last) grapheme equals `grapheme`.
        func words(matching grapheme: String) -> [GateWord] {
            words.filter { entry in
                letterPosition.matches(grapheme: grapheme, in: entry)
                    && entry.image.map { !$0.isEmpty } == true
            }
        }
    }

    nonisolated struct Orb: Equatable, Sendable {
        let id: UUID
        let letter: String
        let word: String
        let imageName: String?
        /// The ring that deflects this orb.
        let ring: CombatDeflectRing
        /// True once the player answered; the scene is animating the consequence.
        var isResolved: Bool
    }

    let config: Config
    private(set) var monsterHP: Int
    private(set) var healthCount: Int
    private(set) var activeOrb: Orb?
    private(set) var outcome: MinigameOutcome?
    private(set) var isActive = false

    private let startingHealth: Int
    private var rng: any RandomNumberGenerator
    /// Ring of the most recently deflected orb; excluded from the next throw's pool.
    private var lastDeflectedRing: CombatDeflectRing?

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
    var rings: [CombatDeflectRing] { CombatDeflectRing.all(count: config.ringCount) }

    mutating func begin() {
        isActive = true
        outcome = nil
        healthCount = startingHealth
        monsterHP = config.monsterHP
        activeOrb = nil
        lastDeflectedRing = nil
    }

    mutating func end() {
        isActive = false
    }

    /// Throws the next orb. Returns no events when inactive, finished, or an orb is live.
    /// Picks a ring letter (excluding the last successful deflect), then a random imaged
    /// word whose start or end matches that grapheme, per `letterPosition`.
    mutating func throwNextOrb() -> [CombatDeflectEvent] {
        guard isActive, outcome == nil, activeOrb == nil, !config.graphemes.isEmpty else {
            return []
        }
        let withWords = config.graphemes.indices.filter { index in
            !config.words(matching: config.graphemes[index].grapheme).isEmpty
        }
        // Prefer a different letter than the last deflect; if that empties the pool
        // (only one letter has imaged words), allow a repeat.
        let excludingLast = withWords.filter { index in
            lastDeflectedRing.map { $0.index != index } ?? true
        }
        let candidates = excludingLast.isEmpty ? withWords : excludingLast
        guard let index = candidates.randomElement(using: &rng) else { return [] }
        let ring = CombatDeflectRing(index)
        let entry = config.graphemes[index]
        let wordChoices = config.words(matching: entry.grapheme)
        guard let word = wordChoices.randomElement(using: &rng) else { return [] }
        let orb = Orb(
            id: UUID(),
            letter: entry.grapheme,
            word: word.word,
            imageName: word.image,
            ring: ring,
            isResolved: false
        )
        activeOrb = orb
        return [
            .throwOrb(
                id: orb.id,
                letter: orb.letter,
                word: orb.word,
                imageName: orb.imageName,
                ring: ring,
                travelSeconds: config.orbTravelSeconds
            ),
            .speakWord(trackID: word.sfx),
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
        guard isActive, outcome == nil, let orb = activeOrb else { return [] }
        lastDeflectedRing = orb.ring
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
