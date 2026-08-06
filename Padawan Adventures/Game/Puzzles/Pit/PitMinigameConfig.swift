import Foundation

/// Discriminator for which pit minigame a pit contact runs. Raw values match YAML `type:`.
nonisolated enum PitMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// Sound out the word one grapheme at a time (`PitSoundOutWordScene`).
    case soundOutWord = "sound-out-word-pit"
    /// Drag lettered floor tiles into slots to bridge the pit (`PitBridgeScene`).
    case bridge = "ending-sound-pit"
    /// Same board, but the tile must match the word's first letter.
    case startingSoundBridge = "starting-sound-pit"
}

/// Per-entry config for the bridge-building pit game.
/// Words come from the level's cumulative `vocab:` pool (imaged entries).
nonisolated struct PitBridgeConfig: Equatable, Sendable {
    var weight: Double
    /// Inclusive lower bound on words (and therefore bridge tiles) per session.
    var minWords: Int
    /// Inclusive upper bound on words per session; the pool must be at least this large.
    var maxWords: Int
    /// Which letter the player supplies: word end (`ending-sound-pit`) or start (`starting-sound-pit`).
    var letterPosition: GateWordPlugLetterPosition
    /// Resolved vocabulary (sorted by word). Populated via `resolve(from:)`.
    var words: [GateWord]
    /// Tier-weighted pool used for word/decoy picks. Populated via `resolve(from:)`.
    var vocabulary: LevelVocabularyPool

    static let defaultMinWords = 2
    static let defaultMaxWords = 4

    nonisolated static let fallback = PitBridgeConfig(
        weight: 1,
        words: WordCatalog.fallback.words.filter {
            $0.graphemes.count >= 2
                && ($0.image?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        }
    )

    nonisolated init(
        weight: Double = 1,
        minWords: Int = defaultMinWords,
        maxWords: Int = defaultMaxWords,
        letterPosition: GateWordPlugLetterPosition = .ending,
        words: [GateWord] = [],
        vocabulary: LevelVocabularyPool? = nil
    ) {
        self.weight = weight
        self.minWords = minWords
        self.maxWords = maxWords
        self.letterPosition = letterPosition
        self.words = GateWord.normalized(words)
        self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(words: self.words)
    }

    /// Imaged words with ≥2 graphemes whose answer grapheme is in the pool.
    mutating func resolve(from pool: LevelVocabularyPool) throws {
        let known = Set(pool.allGraphemes.map(\.grapheme))
        vocabulary = pool.filteringWords { entry in
            guard entry.graphemes.count >= 2,
                  let image = entry.image?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !image.isEmpty,
                  let answer = letterPosition.answerGrapheme(in: entry),
                  known.contains(answer) else {
                return false
            }
            return true
        }
        words = GateWord.normalized(vocabulary.allWords)
    }

    func validate() throws {
        guard minWords >= 1, maxWords >= minWords else {
            throw WorldSeedError.invalidPitBridgeWordRange(min: minWords, max: maxWords)
        }
        guard words.count >= maxWords else {
            throw WorldSeedError.invalidPitBridgeWords
        }
        try CatalogValidators.validateWordEntries(
            words,
            emptyError: .invalidPitBridgeWords,
            invalidEntryError: .invalidPitBridgeWords
        )
        var seen = Set<String>()
        for entry in words {
            guard entry.graphemes.count >= 2,
                  let image = entry.image?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !image.isEmpty,
                  seen.insert(entry.word).inserted else {
                throw WorldSeedError.invalidPitBridgeWords
            }
        }
    }
}

/// Per-entry config for the pit sound-out-word game.
/// Words come from the level's cumulative `vocab:` pool (imaged entries).
/// Graphemes come from the same pool (name/pronunciation audio + decoys).
nonisolated struct PitSoundOutWordConfig: Equatable, Sendable {
    var weight: Double
    /// Inclusive lower bound on tiles offered per grapheme.
    var choiceCountMin: Int
    /// Inclusive upper bound on tiles offered per grapheme.
    var choiceCountMax: Int
    var words: [GateWord]
    /// Resolved grapheme pool. Populated via `resolve(from:)`.
    var graphemes: [GateGrapheme]
    /// Tier-weighted pool used for word picks. Populated via `resolve(from:)`.
    var vocabulary: LevelVocabularyPool

    /// One correct tile plus at least one decoy.
    static let minChoiceCount = 2
    /// Wider fans stop fitting between the pads on phone-sized scenes.
    static let maxChoiceCount = 6

    nonisolated static let fallback = PitSoundOutWordConfig(
        weight: 1,
        words: WordCatalog.fallback.words.filter {
            $0.graphemes.count >= 2
                && ($0.image?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        },
        graphemes: GraphemeCatalog.fallback.graphemes
    )

    nonisolated init(
        weight: Double = 1,
        choiceCountMin: Int = 3,
        choiceCountMax: Int = 3,
        words: [GateWord] = [],
        graphemes: [GateGrapheme] = [],
        vocabulary: LevelVocabularyPool? = nil
    ) {
        self.weight = weight
        self.choiceCountMin = choiceCountMin
        self.choiceCountMax = choiceCountMax
        self.words = GateWord.normalized(words)
        self.graphemes = GateGraphemeMatchConfig.normalizedGraphemes(graphemes)
        self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(
            words: self.words,
            graphemes: self.graphemes
        )
    }

    /// Imaged pool words whose graphemes are all in the pool; graphemes = full pool.
    mutating func resolve(from pool: LevelVocabularyPool) throws {
        let known = Set(pool.allGraphemes.map(\.grapheme))
        vocabulary = pool.filteringWords { entry in
            guard let image = entry.image?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !image.isEmpty,
                  entry.graphemes.count >= 2,
                  entry.graphemes.allSatisfy({ known.contains($0.lowercased()) }) else {
                return false
            }
            return true
        }
        words = GateWord.normalized(vocabulary.allWords)
        graphemes = GateGraphemeMatchConfig.normalizedGraphemes(pool.allGraphemes)
    }

    func validate() throws {
        guard choiceCountMin >= Self.minChoiceCount,
              choiceCountMax >= choiceCountMin,
              choiceCountMax <= Self.maxChoiceCount else {
            throw WorldSeedError.invalidPitSoundOutWordChoiceRange(
                min: choiceCountMin,
                max: choiceCountMax
            )
        }
        try CatalogValidators.validateWordEntries(
            words,
            emptyError: .invalidPitSoundOutWordWords,
            invalidEntryError: .invalidPitSoundOutWordWords
        )
        var seen = Set<String>()
        for entry in words {
            guard entry.graphemes.count >= 2,
                  let image = entry.image?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !image.isEmpty,
                  seen.insert(entry.word).inserted else {
                throw WorldSeedError.invalidPitSoundOutWordWords
            }
        }
        let known = Set(graphemes.map(\.grapheme))
        guard known.count >= choiceCountMax else {
            throw WorldSeedError.invalidPitSoundOutWordGraphemes
        }
        for entry in words {
            for grapheme in entry.graphemes {
                guard known.contains(grapheme.lowercased()) else {
                    throw WorldSeedError.invalidPitSoundOutWordGraphemes
                }
            }
        }
    }
}

/// Discriminated union over the pit minigame entries in level YAML.
nonisolated enum PitMinigameConfig: Equatable, Sendable {
    case soundOutWord(PitSoundOutWordConfig)
    case bridge(PitBridgeConfig)

    var kind: PitMinigameKind {
        switch self {
        case .soundOutWord: .soundOutWord
        // Both bridge YAML types share this case; the mode picks the kind.
        case .bridge(let config):
            config.letterPosition == .starting ? .startingSoundBridge : .bridge
        }
    }

    /// Relative pick weight; negatives are rejected by `PitConfig.validate()`.
    var weight: Double {
        switch self {
        case .soundOutWord(let config): config.weight
        case .bridge(let config): config.weight
        }
    }
}

/// Resolved pit host config from level YAML `pit:`.
nonisolated struct PitConfig: Equatable, Sendable {
    /// Shared pit FX: `jump` fires on every hop, `lose` / `win` override `audio.yaml`.
    var fx: SoundEffectTable
    /// Music track basename for pit minigames; `nil` → inherit from audio.yaml.
    var music: String?
    var minigames: [PitMinigameConfig]

    /// Used when a level omits `pit:` entirely — sound-out-word only.
    nonisolated static let fallback = PitConfig(
        fx: SoundEffectTable(events: [
            "jump": "pit-jump",
        ]),
        music: "pit",
        minigames: [.soundOutWord(.fallback)]
    )

    nonisolated init(fx: SoundEffectTable, music: String? = nil, minigames: [PitMinigameConfig]) {
        self.fx = fx
        self.music = music
        self.minigames = minigames
    }

    func minigame(for kind: PitMinigameKind) -> PitMinigameConfig? {
        minigames.first { $0.kind == kind }
    }

    /// Weighted pick, same semantics as `CombatConfig.pickMinigame`: weight 0 is never
    /// chosen unless every weight is 0, in which case the first entry wins.
    func pickMinigame(using rng: inout some RandomNumberGenerator) throws -> PitMinigameConfig {
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("pit.minigames must not be empty")
        }
        guard let picked = WeightedPicker.pick(from: minigames, weight: \.weight, using: &rng) else {
            throw WorldSeedError.decodeFailed("pit.minigames must not be empty")
        }
        return picked
    }

    mutating func resolveMinigames(from pool: LevelVocabularyPool) throws {
        for index in minigames.indices {
            switch minigames[index] {
            case .soundOutWord(var config):
                try config.resolve(from: pool)
                minigames[index] = .soundOutWord(config)
            case .bridge(var config):
                try config.resolve(from: pool)
                minigames[index] = .bridge(config)
            }
        }
    }

    func validate() throws {
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("pit.minigames must not be empty")
        }
        var seenKinds = Set<PitMinigameKind>()
        for entry in minigames {
            guard entry.weight >= 0 else {
                throw WorldSeedError.invalidPitMinigameWeight(entry.weight)
            }
            guard seenKinds.insert(entry.kind).inserted else {
                throw WorldSeedError.decodeFailed(
                    "pit.minigames has duplicate type '\(entry.kind.rawValue)'"
                )
            }
            switch entry {
            case .soundOutWord(let config): try config.validate()
            case .bridge(let config): try config.validate()
            }
        }
    }
}
