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
        /// Candidate ring graphemes (those with ≥1 matching imaged word). The fight
        /// samples `ringCount` of these at `begin()`.
        var graphemes: [GateGrapheme]
        /// How many rings to draw this fight, clamped to the candidate count.
        var ringCount: Int
        /// Vocabulary used to pick a thrown word for each letter (typically the full catalog).
        var words: [GateWord]
        /// Tier-weighted pool used for ring and word picks.
        var vocabulary: LevelVocabularyPool
        var monsterHP: Int
        var orbTravelSeconds: Double
        var letterPosition: GateWordPlugLetterPosition

        init(
            graphemes: [GateGrapheme],
            words: [GateWord] = WordCatalog.fallback.words,
            monsterHP: Int,
            orbTravelSeconds: Double,
            letterPosition: GateWordPlugLetterPosition = .starting,
            ringCount: Int? = nil,
            vocabulary: LevelVocabularyPool? = nil
        ) {
            self.graphemes = graphemes
            self.words = words
            self.monsterHP = max(monsterHP, 1)
            self.orbTravelSeconds = max(orbTravelSeconds, 0.2)
            self.letterPosition = letterPosition
            // Tests may pass a 1-letter pool; production `resolve` already clamps to 2...6.
            self.ringCount = ringCount ?? graphemes.count
            self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(
                words: self.words,
                graphemes: self.graphemes
            )
        }

        init(from deflect: CombatDeflectConfig) {
            self.init(
                graphemes: deflect.graphemes,
                words: deflect.words.isEmpty ? WordCatalog.fallback.words : deflect.words,
                monsterHP: deflect.monsterHP,
                orbTravelSeconds: deflect.orbTravelSeconds,
                letterPosition: deflect.letterPosition,
                ringCount: deflect.ringCount,
                vocabulary: deflect.vocabulary
            )
        }

        /// Imaged vocabulary entries whose first (or last) grapheme equals `grapheme`.
        func words(matching grapheme: String) -> [GateWord] {
            words.filter { entry in
                letterPosition.matches(grapheme: grapheme, in: entry)
                    && entry.image.map { !$0.isEmpty } == true
            }
        }

        /// Throw candidates for `grapheme` among `rings`: imaged, matching, and visually
        /// unambiguous. Prefers spellings not in `excluding` when any remain.
        func throwWords(
            matching grapheme: String,
            among rings: Set<String>,
            excluding usedWords: Set<String> = [],
            isPlausibleSpelling: @escaping @Sendable (String) -> Bool = CombatDeflectMinigameEngine.isPlausibleSpelling
        ) -> [GateWord] {
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

        /// Back-compat for tests that omit `among:` — uses every candidate grapheme as a ring.
        func throwWords(
            matching grapheme: String,
            excluding usedWords: Set<String> = [],
            isPlausibleSpelling: @escaping @Sendable (String) -> Bool = CombatDeflectMinigameEngine.isPlausibleSpelling
        ) -> [GateWord] {
            throwWords(
                matching: grapheme,
                among: Set(graphemes.map(\.grapheme)),
                excluding: usedWords,
                isPlausibleSpelling: isPlausibleSpelling
            )
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
    /// Rings drawn this fight, left to right. Sampled at `begin()` from `config.graphemes`.
    private(set) var graphemes: [GateGrapheme]
    private(set) var monsterHP: Int
    private(set) var healthCount: Int
    private(set) var activeOrb: Orb?
    private(set) var outcome: MinigameOutcome?
    private(set) var isActive = false

    private let startingHealth: Int
    private var rng: any RandomNumberGenerator
    private let sampler: LevelVocabularySampler
    /// Ring of the most recently deflected orb; excluded from the next throw's pool.
    private var lastDeflectedRing: CombatDeflectRing?
    /// Optional override for tests; defaults to catalog + known collision spellings.
    private let isPlausibleSpelling: @Sendable (String) -> Bool

    init(
        config: Config,
        startingHealth: Int = 3,
        rng: some RandomNumberGenerator = SystemRandomNumberGenerator(),
        isPlausibleSpelling: @escaping @Sendable (String) -> Bool = CombatDeflectMinigameEngine.isPlausibleSpelling,
        sampler: LevelVocabularySampler? = nil
    ) {
        self.config = config
        self.graphemes = config.graphemes
        self.startingHealth = max(startingHealth, 0)
        self.healthCount = self.startingHealth
        self.monsterHP = config.monsterHP
        self.rng = rng
        self.sampler = sampler ?? LevelVocabularySampler(pool: config.vocabulary)
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
    var rings: [CombatDeflectRing] { CombatDeflectRing.all(count: graphemes.count) }
    var ringGraphemes: Set<String> { Set(graphemes.map(\.grapheme)) }

    mutating func begin() {
        isActive = true
        outcome = nil
        healthCount = startingHealth
        monsterHP = config.monsterHP
        activeOrb = nil
        lastDeflectedRing = nil
        graphemes = pickFightRings()
    }

    mutating func end() {
        isActive = false
    }

    /// Throws the next orb. Returns no events when inactive, finished, or an orb is live.
    /// Picks a word from the cumulative pool without replacement (current-level words
    /// more likely), then the ring whose grapheme matches that word. Unused spellings
    /// are preferred until the unambiguous pool is exhausted.
    mutating func throwNextOrb() -> [CombatDeflectEvent] {
        guard isActive, outcome == nil, activeOrb == nil, !graphemes.isEmpty else {
            return []
        }
        let rings = ringGraphemes
        let excludingLast: Set<String> = {
            guard let last = lastDeflectedRing, graphemes.indices.contains(last.index) else {
                return rings
            }
            var allowed = rings
            allowed.remove(graphemes[last.index].grapheme)
            return allowed.isEmpty ? rings : allowed
        }()
        guard let word = pickThrowWord(among: excludingLast)
            ?? pickThrowWord(among: rings),
              let answer = config.letterPosition.answerGrapheme(in: word),
              let index = graphemes.firstIndex(where: { $0.grapheme == answer }) else {
            return []
        }
        let ring = CombatDeflectRing(index)
        let orb = Orb(
            id: UUID(),
            letter: answer,
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

    /// Samples `config.ringCount` graphemes without replacement from the candidates.
    /// When the candidate list is already that size (typical in tests), it is kept as-is.
    private mutating func pickFightRings() -> [GateGrapheme] {
        let desired = min(max(config.ringCount, 1), config.graphemes.count)
        guard desired > 0 else { return [] }
        if config.graphemes.count <= desired {
            return config.graphemes
        }
        let allowed = Set(config.graphemes.map { $0.grapheme.lowercased() })
        let picked = sampler.takeGraphemes(
            count: desired,
            where: { allowed.contains($0.grapheme.lowercased()) },
            using: &rng
        )
        if picked.count == desired {
            return picked
        }
        return Array(config.graphemes.prefix(desired))
    }

    /// Weighted pick from the cumulative pool: imaged, unambiguous among the fight's
    /// rings, matching one of `allowed`. Recycles after the unused set is exhausted.
    private mutating func pickThrowWord(among allowed: Set<String>) -> GateWord? {
        let rings = ringGraphemes
        let letterPosition = config.letterPosition
        let vocabulary = config.words
        let plausible = isPlausibleSpelling
        var localRng = rng
        let picked = sampler.nextWord(where: { entry in
            guard entry.image.map({ !$0.isEmpty }) == true,
                  let answer = letterPosition.answerGrapheme(in: entry),
                  allowed.contains(answer) else {
                return false
            }
            return letterPosition.hasUniqueAnswer(
                in: entry,
                among: rings,
                vocabulary: vocabulary,
                isPlausibleSpelling: plausible
            )
        }, using: &localRng)
        rng = localRng
        return picked
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
