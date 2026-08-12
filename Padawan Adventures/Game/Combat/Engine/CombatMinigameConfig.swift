import Foundation

/// Discriminator for which combat minigame an encounter runs. Raw values match YAML `type:`.
nonisolated enum CombatMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// The original swipe-to-slash arena (`CombatScene`).
    case slash = "grapheme-sound-combat"
    /// Tap-the-matching-ring deflect arena, keyed on the word's first grapheme (`CombatDeflectScene`).
    case startingSoundDeflect = "starting-sound-combat"
    /// Same arena, keyed on the word's last grapheme.
    case endingSoundDeflect = "ending-sound-combat"
}

/// Combat kind + pick weight used during generation.
nonisolated struct WeightedCombatKind: Equatable, Sendable {
    var kind: CombatMinigameKind
    var weight: Double
}

/// Per-entry config for the slash arena.
nonisolated struct CombatSlashConfig: Equatable, Sendable {
    var weight: Double
    /// Extra non-matching letters launched alongside the cued one, per wave.
    var minDecoyCount: Int
    var maxDecoyCount: Int
    /// Casing for combat projectile / cue letters, drawn after identity.
    /// Applies to single letters only; multi-letter graphemes stay lowercase.
    var graphemeCase: CombatGraphemeCase
    /// Pronunciation prompt replay interval in seconds.
    var graphemeSoundRepeatSeconds: Double
    /// Single-character graphemes from the cumulative vocab pool. Populated via `resolve(from:)`.
    var vocabulary: LevelVocabularyPool

    nonisolated static let fallback = CombatSlashConfig(weight: 1)

    nonisolated init(
        weight: Double = 1,
        minDecoyCount: Int = CombatMinigameEngine.Config.defaultMinDecoyCount,
        maxDecoyCount: Int = CombatMinigameEngine.Config.defaultMaxDecoyCount,
        graphemeCase: CombatGraphemeCase = .upper,
        graphemeSoundRepeatSeconds: Double = 3,
        vocabulary: LevelVocabularyPool? = nil
    ) {
        self.weight = weight
        self.minDecoyCount = minDecoyCount
        self.maxDecoyCount = maxDecoyCount
        self.graphemeCase = graphemeCase
        self.graphemeSoundRepeatSeconds = graphemeSoundRepeatSeconds
        self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(
            graphemes: GraphemeCatalog.fallback.graphemes.filter { $0.grapheme.count == 1 }
        )
    }

    /// Keeps single-character graphemes so slash shots stay one glyph.
    mutating func resolve(from pool: LevelVocabularyPool) {
        let filtered = pool.filteringGraphemes { $0.grapheme.count == 1 }
        if !filtered.allGraphemes.isEmpty {
            vocabulary = filtered
        }
    }

    func validate() throws {
        guard minDecoyCount >= 1,
              maxDecoyCount >= minDecoyCount,
              maxDecoyCount <= 8 else {
            throw WorldSeedError.invalidCombatDecoyCount(min: minDecoyCount, max: maxDecoyCount)
        }
        guard graphemeSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidGraphemeSoundRepeat(graphemeSoundRepeatSeconds)
        }
    }
}

/// Per-entry config for the deflect arena.
nonisolated struct CombatDeflectConfig: Equatable, Sendable {
    var weight: Double
    /// Monster hit points; also the star award on win.
    var monsterHP: Int
    /// Seconds for an orb to fly from the monster to the player.
    var orbTravelSeconds: Double
    /// Which grapheme the ring must match: word start (`starting-sound-combat`)
    /// or word end (`ending-sound-combat`).
    var letterPosition: GateWordPlugLetterPosition
    /// How many deflection rings to draw (`minRingCount`...`maxRingCount`).
    /// Clamped at `resolve(from:)` to the candidate grapheme count.
    var ringCount: Int
    /// Graphemes that have ≥1 matching imaged word. The fight samples `ringCount`
    /// of these without replacement (current-level graphemes more likely).
    var graphemes: [GateGrapheme]
    /// Imaged vocabulary used to throw orbs. Populated via `resolve(from:)`.
    var words: [GateWord]
    /// Tier-weighted pool used for ring and word picks. Populated via `resolve(from:)`.
    var vocabulary: LevelVocabularyPool

    static let defaultMonsterHP = 5
    static let defaultOrbTravelSeconds: Double = 6
    static let minRingCount = 2
    static let maxRingCount = 6
    /// Used when YAML omits `ring_count:` (and for the code fallback).
    static let defaultRingCount = 4

    nonisolated static let fallback = CombatDeflectConfig(
        weight: 1,
        ringCount: defaultRingCount,
        graphemes: Array(
            GraphemeCatalog.fallback.graphemes
                .filter { $0.grapheme.count == 1 }
                .prefix(defaultRingCount)
        ),
        words: WordCatalog.fallback.words.filter { $0.image.map { !$0.isEmpty } == true }
    )

    nonisolated init(
        weight: Double = 1,
        monsterHP: Int = defaultMonsterHP,
        orbTravelSeconds: Double = defaultOrbTravelSeconds,
        letterPosition: GateWordPlugLetterPosition = .starting,
        ringCount: Int = defaultRingCount,
        graphemes: [GateGrapheme] = [],
        words: [GateWord] = [],
        vocabulary: LevelVocabularyPool? = nil
    ) {
        self.weight = weight
        self.monsterHP = monsterHP
        self.orbTravelSeconds = orbTravelSeconds
        self.letterPosition = letterPosition
        self.ringCount = ringCount
        self.graphemes = graphemes
        self.words = GateWord.normalized(words)
        self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(
            words: self.words,
            graphemes: self.graphemes
        )
    }

    /// Candidates are graphemes that have ≥1 imaged word matching `letterPosition`.
    /// `ringCount` is clamped to `minRingCount`...`min(candidates.count, maxRingCount)`.
    /// The fight samples that many rings and throws words from the cumulative pool
    /// without replacement, with current-level entries more likely.
    mutating func resolve(from pool: LevelVocabularyPool) throws {
        vocabulary = pool.filteringWords { entry in
            entry.image.map { !$0.isEmpty } == true
        }
        words = GateWord.normalized(vocabulary.allWords)
        let imaged = vocabulary.allWords
        let candidates = pool.allGraphemes.filter { grapheme in
            imaged.contains { letterPosition.matches(grapheme: grapheme.grapheme, in: $0) }
        }
        guard candidates.count >= Self.minRingCount else {
            throw WorldSeedError.invalidCombatDeflectGraphemes
        }
        ringCount = min(max(ringCount, Self.minRingCount), candidates.count, Self.maxRingCount)
        graphemes = candidates
    }

    func validate() throws {
        guard monsterHP >= 1 else {
            throw WorldSeedError.invalidCombatMonsterHP(monsterHP)
        }
        guard orbTravelSeconds > 0 else {
            throw WorldSeedError.invalidCombatOrbTravelSeconds(orbTravelSeconds)
        }
        guard graphemes.count >= Self.minRingCount,
              (Self.minRingCount...Self.maxRingCount).contains(ringCount),
              ringCount <= graphemes.count else {
            throw WorldSeedError.invalidCombatDeflectGraphemes
        }
        try CatalogValidators.validateGraphemeEntries(
            graphemes,
            requirePronunciation: false,
            emptyError: .invalidCombatDeflectGraphemes,
            invalidEntryError: .invalidCombatDeflectGraphemes
        )
    }
}

/// Discriminated union over the combat minigame entries in level YAML.
nonisolated enum CombatMinigameConfig: Equatable, Sendable {
    case slash(CombatSlashConfig)
    case deflect(CombatDeflectConfig)

    var kind: CombatMinigameKind {
        switch self {
        case .slash: .slash
        // Both deflect YAML types share this case; the letter position picks the kind.
        case .deflect(let config):
            config.letterPosition == .ending ? .endingSoundDeflect : .startingSoundDeflect
        }
    }

    /// Relative pick weight; negatives are rejected by `CombatConfig.validate()`.
    var weight: Double {
        switch self {
        case .slash(let config): config.weight
        case .deflect(let config): config.weight
        }
    }
}

/// Resolved combat host config from level YAML `combat:`.
nonisolated struct CombatConfig: Equatable, Sendable {
    /// Music track basename for combat minigames; `nil` → inherit from audio.yaml.
    var music: String?
    var minigames: [CombatMinigameConfig]

    /// Used when a level omits `combat:` entirely — slash only, preserving old behaviour.
    nonisolated static let fallback = CombatConfig(music: "combat", minigames: [.slash(.fallback)])

    nonisolated init(music: String? = nil, minigames: [CombatMinigameConfig]) {
        self.music = music
        self.minigames = minigames
    }

    func minigame(for kind: CombatMinigameKind) -> CombatMinigameConfig? {
        minigames.first { $0.kind == kind }
    }

    /// Combat kinds with their pick weights, in declaration order.
    var weightedMinigameKinds: [WeightedCombatKind] {
        minigames.map { WeightedCombatKind(kind: $0.kind, weight: $0.weight) }
    }

    /// One-shot weighted pick used when an enemy has no generation pin (legacy saves).
    /// New worlds bake kinds without replacement so equal weights yield equal counts.
    /// Weight 0 is never chosen unless every weight is 0, in which case the first entry wins.
    func pickMinigame(using rng: inout some RandomNumberGenerator) throws -> CombatMinigameConfig {
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        guard let picked = WeightedPicker.pick(from: minigames, weight: \.weight, using: &rng) else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        return picked
    }

    mutating func resolveGraphemes(from pool: LevelVocabularyPool) throws {
        for index in minigames.indices {
            switch minigames[index] {
            case .slash(var config):
                config.resolve(from: pool)
                minigames[index] = .slash(config)
            case .deflect(var config):
                try config.resolve(from: pool)
                minigames[index] = .deflect(config)
            }
        }
    }

    func validate() throws {
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        var seenKinds = Set<CombatMinigameKind>()
        for entry in minigames {
            guard entry.weight >= 0 else {
                throw WorldSeedError.invalidCombatMinigameWeight(entry.weight)
            }
            guard seenKinds.insert(entry.kind).inserted else {
                throw WorldSeedError.decodeFailed(
                    "combat.minigames has duplicate type '\(entry.kind.rawValue)'"
                )
            }
            switch entry {
            case .slash(let config): try config.validate()
            case .deflect(let config): try config.validate()
            }
        }
    }
}
