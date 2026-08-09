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
    /// `letter` is the ring that deflects this orb; `word` / `sfx` drive the thrown
    /// sprite text and its pronunciation.
    case throwOrb(
        id: UUID,
        letter: String,
        word: String,
        sfx: String,
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

        /// Ring grapheme strings left to right.
        var ringGraphemes: Set<String> {
            Set(graphemes.map(\.grapheme))
        }

        /// Imaged vocabulary entries whose first (or last) grapheme equals `grapheme`.
        func words(matching grapheme: String) -> [GateWord] {
            words.filter { entry in
                letterPosition.matches(grapheme: grapheme, in: entry)
                    && entry.image.map { !$0.isEmpty } == true
            }
        }

        /// Throw candidates for `grapheme`: imaged, matching, and visually unambiguous among
        /// the rings. Prefers spellings not in `excluding` when any remain.
        func throwWords(
            matching grapheme: String,
            excluding usedWords: Set<String> = [],
            isPlausibleSpelling: @escaping @Sendable (String) -> Bool = CombatDeflectMinigameEngine.isPlausibleSpelling
        ) -> [GateWord] {
            let rings = ringGraphemes
            let unambiguous = words(matching: grapheme).filter { entry in
                letterPosition.hasUniqueAnswer(
                    in: entry,
                    among: rings,
                    vocabulary: words,
                    isPlausibleSpelling: isPlausibleSpelling
                )
            }
            let unused = unambiguous.filter { !usedWords.contains($0.word) }
            return unused.isEmpty ? unambiguous : unused
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
    /// Spellings already thrown this fight; preferred against when picking the next word.
    private var usedWords: Set<String>
    /// Optional override for tests; defaults to catalog + known collision spellings.
    private let isPlausibleSpelling: @Sendable (String) -> Bool

    init(
        config: Config,
        startingHealth: Int = 3,
        rng: some RandomNumberGenerator = SystemRandomNumberGenerator(),
        isPlausibleSpelling: @escaping @Sendable (String) -> Bool = CombatDeflectMinigameEngine.isPlausibleSpelling
    ) {
        self.config = config
        self.startingHealth = max(startingHealth, 0)
        self.healthCount = self.startingHealth
        self.monsterHP = config.monsterHP
        self.rng = rng
        self.usedWords = []
        self.isPlausibleSpelling = isPlausibleSpelling
    }

    /// Spellings that aren't in `words.yaml` but still collide with a curriculum blank
    /// (e.g. English `trip` beside game word `tris`). Keep this list tiny — a full
    /// dictionary check (UITextChecker) rejects nearly every short CVC stem and leaves
    /// the tutorial with no orb to throw.
    nonisolated private static let extraCollisionSpellings: Set<String> = [
        "trip",
    ]

    /// True when `spelling` is a catalog word or a known collision spelling.
    /// Used so distractor rings cannot complete the same blank into another real word.
    nonisolated static let isPlausibleSpelling: @Sendable (String) -> Bool = { spelling in
        let key = spelling.lowercased()
        guard !key.isEmpty else { return false }
        if WordCatalog.fallback.word(named: key) != nil { return true }
        return Self.extraCollisionSpellings.contains(key)
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
        usedWords = []
    }

    mutating func end() {
        isActive = false
    }

    /// Throws the next orb. Returns no events when inactive, finished, or an orb is live.
    /// Picks a ring letter (excluding the last successful deflect), then a random imaged
    /// word whose start or end matches that grapheme, per `letterPosition`. Words are
    /// required to have a unique right answer among the rings, and unused spellings are
    /// preferred until the unambiguous pool is exhausted.
    mutating func throwNextOrb() -> [CombatDeflectEvent] {
        guard isActive, outcome == nil, activeOrb == nil, !config.graphemes.isEmpty else {
            return []
        }
        let withWords = config.graphemes.indices.filter { index in
            !config.throwWords(
                matching: config.graphemes[index].grapheme,
                excluding: usedWords,
                isPlausibleSpelling: isPlausibleSpelling
            ).isEmpty
        }
        // Prefer a different letter than the last deflect; if that empties the pool
        // (only one letter has unambiguous words), allow a repeat.
        let excludingLast = withWords.filter { index in
            lastDeflectedRing.map { $0.index != index } ?? true
        }
        let candidates = excludingLast.isEmpty ? withWords : excludingLast
        guard let index = candidates.randomElement(using: &rng) else { return [] }
        let ring = CombatDeflectRing(index)
        let entry = config.graphemes[index]
        let wordChoices = config.throwWords(
            matching: entry.grapheme,
            excluding: usedWords,
            isPlausibleSpelling: isPlausibleSpelling
        )
        guard let word = wordChoices.randomElement(using: &rng) else { return [] }
        usedWords.insert(word.word)
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
                sfx: word.sfx,
                ring: ring,
                travelSeconds: config.orbTravelSeconds
            ),
            .speakWord(trackID: word.sfx),
        ]
    }

    /// Player tapped `ring`. A correct tap marks the orb resolved so a second tap cannot
    /// double-fire; a wrong tap leaves it live so the player can keep trying. The scene
    /// animates the consequence and, on a correct hit, calls `registerOrbReachedMonster`
    /// when the return flight lands.
    mutating func registerTap(ring: CombatDeflectRing) -> CombatDeflectTapResult {
        guard isActive, outcome == nil, var orb = activeOrb, !orb.isResolved else {
            return .ignored
        }
        if orb.ring == ring {
            orb.isResolved = true
            activeOrb = orb
            return .correct(orb.ring)
        }
        return .wrong(ring)
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

    /// The orb reached the player untapped: -1 heart, maybe lose.
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
