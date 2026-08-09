import Foundation

/// Per-entry gate sound-out-word config: sound out the prompted word one letter at a time,
/// dragging the right capacitor out of each offered set.
/// Vocabulary comes from the level's cumulative `vocab:` pool.
nonisolated struct GateSoundOutWordConfig: Equatable, Sendable {
    /// Relative pick weight within `gate.minigames`.
    var weight: Double
    /// In-puzzle FX (optional `win` override for shared `sound.yaml`).
    var fx: SoundEffectTable
    /// Inclusive lower bound on capacitors offered per letter.
    var choiceCountMin: Int
    /// Inclusive upper bound on capacitors offered per letter.
    var choiceCountMax: Int
    /// Resolved vocabulary (sorted by word). Populated via `resolve(from:)`.
    var words: [GateWord]
    /// Resolved letter pool. Populated via `resolve(from:)`.
    var graphemes: [GateGrapheme]
    /// Tier-weighted pool used for word picks. Populated via `resolve(from:)`.
    var vocabulary: LevelVocabularyPool
    /// Per-entry music override; `nil` → use `gate.music`.
    var music: String?

    /// One correct capacitor plus at least one decoy.
    nonisolated static let minChoiceCount = 2
    /// Wider sets stop fitting the bottom row on phone-sized scenes.
    nonisolated static let maxChoiceCount = 6

    nonisolated static let fallback = GateSoundOutWordConfig(
        weight: 1,
        choiceCountMin: 2,
        choiceCountMax: 4,
        words: WordCatalog.fallback.words,
        graphemes: GraphemeCatalog.fallback.graphemes,
        music: "gate"
    )

    nonisolated init(
        weight: Double = 1,
        fx: SoundEffectTable = SoundEffectTable(),
        choiceCountMin: Int = 2,
        choiceCountMax: Int = 4,
        words: [GateWord],
        graphemes: [GateGrapheme],
        vocabulary: LevelVocabularyPool? = nil,
        music: String? = nil
    ) {
        self.weight = weight
        self.fx = fx
        self.choiceCountMin = choiceCountMin
        self.choiceCountMax = choiceCountMax
        self.words = GateWord.normalized(words)
        self.graphemes = GateGraphemeMatchConfig.normalizedGraphemes(graphemes)
        self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(
            words: self.words,
            graphemes: self.graphemes
        )
        self.music = music
    }

    /// Any pool words whose graphemes are all in the pool; graphemes = full pool.
    mutating func resolve(from pool: LevelVocabularyPool) throws {
        let known = Set(pool.allGraphemes.map(\.grapheme))
        vocabulary = pool.filteringWords { entry in
            entry.graphemes.allSatisfy { known.contains($0.lowercased()) }
        }
        words = GateWord.normalized(vocabulary.allWords)
        graphemes = GateGraphemeMatchConfig.normalizedGraphemes(pool.allGraphemes)
    }

    func validate() throws {
        guard choiceCountMin >= Self.minChoiceCount,
              choiceCountMax >= choiceCountMin,
              choiceCountMax <= Self.maxChoiceCount else {
            throw WorldSeedError.invalidGateSoundOutWordChoiceRange(
                min: choiceCountMin,
                max: choiceCountMax
            )
        }
        try CatalogValidators.validateWordEntries(
            words,
            emptyError: .invalidGateWords,
            invalidEntryError: .invalidGateWords
        )
        let known = Set(graphemes.map(\.grapheme))
        guard known.count >= choiceCountMax else {
            throw WorldSeedError.invalidGateSoundOutWordLetters
        }
        for entry in words {
            for grapheme in entry.graphemes {
                guard known.contains(grapheme.lowercased()) else {
                    throw WorldSeedError.invalidGateSoundOutWordLetters
                }
            }
        }
    }
}

/// A gate letter-match puzzle letter: glyph + pronunciation/name track basenames.
nonisolated struct GateGrapheme: Equatable, Sendable {
    var grapheme: String
    var pronunciation: String
    var name: String
}

/// Per-entry gate letter-matching config.
/// Letters come from the level's cumulative `vocab:` pool.
nonisolated struct GateGraphemeMatchConfig: Equatable, Sendable {
    /// Relative pick weight within `gate.minigames`.
    var weight: Double
    /// Inclusive lower bound for letters chosen per round (clamped to the letter pool).
    var graphemeCountMin: Int
    /// Inclusive upper bound for letters chosen per round (clamped to the letter pool).
    var graphemeCountMax: Int
    /// In-puzzle FX (optional `correct` override for shared `sound.yaml`).
    var fx: SoundEffectTable
    /// Resolved letters (sorted). Populated via `resolve(from:)`.
    var graphemes: [GateGrapheme]
    /// Tier-weighted pool used for grapheme picks. Populated via `resolve(from:)`.
    var vocabulary: LevelVocabularyPool
    /// Per-entry music override; `nil` → use `gate.music`.
    var music: String?

    nonisolated static let fallback = GateGraphemeMatchConfig(
        weight: 1,
        graphemeCountMin: 4,
        graphemeCountMax: 8,
        graphemes: GraphemeCatalog.fallback.graphemes,
        music: "gate"
    )

    nonisolated init(
        weight: Double = 1,
        graphemeCountMin: Int = 4,
        graphemeCountMax: Int = 8,
        fx: SoundEffectTable = SoundEffectTable(),
        graphemes: [GateGrapheme],
        vocabulary: LevelVocabularyPool? = nil,
        music: String? = nil
    ) {
        self.weight = weight
        self.graphemeCountMin = graphemeCountMin
        self.graphemeCountMax = graphemeCountMax
        self.fx = fx
        self.graphemes = Self.normalizedGraphemes(graphemes)
        self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(graphemes: self.graphemes)
        self.music = music
    }

    mutating func resolve(from pool: LevelVocabularyPool) throws {
        vocabulary = pool
        graphemes = Self.normalizedGraphemes(pool.allGraphemes)
    }

    func validate() throws {
        guard graphemeCountMin >= 1, graphemeCountMax >= graphemeCountMin else {
            throw WorldSeedError.invalidGateGraphemeMatchCountRange(
                min: graphemeCountMin,
                max: graphemeCountMax
            )
        }
        guard !graphemes.isEmpty else {
            throw WorldSeedError.invalidGateGraphemeMatchGraphemes
        }
        try CatalogValidators.validateGraphemeEntries(
            graphemes,
            requirePronunciation: true,
            emptyError: .invalidGateGraphemeMatchGraphemes,
            invalidEntryError: .invalidGateGraphemeMatchGraphemes
        )
    }

    static func normalizedGraphemes(_ graphemes: [GateGrapheme]) -> [GateGrapheme] {
        graphemes
            .map {
                GateGrapheme(
                    grapheme: $0.grapheme.lowercased(),
                    pronunciation: $0.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .sorted { $0.grapheme < $1.grapheme }
    }
}

/// Which grapheme of the word the player must plug in.
nonisolated enum GateWordPlugLetterPosition: String, Equatable, Sendable {
    case starting
    case ending

    /// Lowercased answer grapheme; `nil` when the entry has no graphemes.
    func answerGrapheme(in entry: GateWord) -> String? {
        switch self {
        case .starting: return entry.graphemes.first
        case .ending: return entry.graphemes.last
        }
    }

    /// Console mask blanking the answer grapheme's full character span:
    /// `stop` starting → `__op`; `high` ending → `h___`.
    func maskedText(for entry: GateWord) -> String {
        guard let answer = answerGrapheme(in: entry) else { return entry.word }
        let blanks = String(repeating: "_", count: answer.count)
        switch self {
        case .starting: return blanks + entry.word.dropFirst(answer.count)
        case .ending: return String(entry.word.dropLast(answer.count)) + blanks
        }
    }

    /// True when `entry`'s first (or last) grapheme equals `grapheme`.
    func matches(grapheme: String, in entry: GateWord) -> Bool {
        let key = grapheme.lowercased()
        guard !key.isEmpty else { return false }
        switch self {
        case .starting: return entry.graphemes.first == key
        case .ending: return entry.graphemes.last == key
        }
    }

    /// Characters that stay visible after blanking the answer grapheme (`tri` for `tris` ending).
    func characterStem(in entry: GateWord) -> String? {
        guard let answer = answerGrapheme(in: entry),
              answer.count <= entry.word.count else { return nil }
        switch self {
        case .starting: return String(entry.word.dropFirst(answer.count))
        case .ending: return String(entry.word.dropLast(answer.count))
        }
    }

    /// Spelling formed by pairing `stem` with `grapheme` in this letter position.
    func completedSpelling(stem: String, grapheme: String) -> String {
        switch self {
        case .starting: return grapheme + stem
        case .ending: return stem + grapheme
        }
    }

    /// True when no other ring grapheme could complete the same visible mask into another
    /// vocabulary word (or any spelling `isPlausibleSpelling` accepts — e.g. English `trip`
    /// beside game word `tris`).
    func hasUniqueAnswer(
        in entry: GateWord,
        among ringGraphemes: Set<String>,
        vocabulary: [GateWord],
        isPlausibleSpelling: @Sendable (String) -> Bool = { _ in false }
    ) -> Bool {
        guard let answer = answerGrapheme(in: entry),
              ringGraphemes.contains(answer) else { return false }
        let mask = maskedText(for: entry)
        var competingAnswers = Set<String>()
        for other in vocabulary {
            guard let otherAnswer = answerGrapheme(in: other),
                  ringGraphemes.contains(otherAnswer),
                  maskedText(for: other) == mask else { continue }
            competingAnswers.insert(otherAnswer)
        }
        if competingAnswers.count > 1 { return false }

        guard let stem = characterStem(in: entry) else { return false }
        for ring in ringGraphemes where ring != answer && ring.count == answer.count {
            let spelling = completedSpelling(stem: stem, grapheme: ring)
            if spelling != entry.word, isPlausibleSpelling(spelling) {
                return false
            }
        }
        return true
    }
}

/// Per-entry gate word-plug config: match each word's missing first or last letter (see `letterPosition`).
/// Words and letters come from the level's cumulative `vocab:` pool.
nonisolated struct GateWordPlugConfig: Equatable, Sendable {
    /// Relative pick weight within `gate.minigames`.
    var weight: Double
    /// Inclusive lower bound for words per round (>= 1).
    var wordCountMin: Int
    /// Inclusive upper bound for words per round (<= `maxWordsPerRound`).
    var wordCountMax: Int
    /// Which letter the player supplies: word start (`starting-sound-gate`) or word end (`ending-sound-gate`).
    var letterPosition: GateWordPlugLetterPosition
    var fx: SoundEffectTable
    /// Resolved vocabulary (sorted by word). Populated via `resolve(from:)`.
    var words: [GateWord]
    /// Resolved letter pool. Populated via `resolve(from:)`.
    var graphemes: [GateGrapheme]
    /// Tier-weighted pool used for word picks. Populated via `resolve(from:)`.
    var vocabulary: LevelVocabularyPool
    /// Per-entry music override; `nil` → use `gate.music`.
    var music: String?

    /// Up to 3 columns x 3 rows of word plates.
    nonisolated static let maxWordsPerRound = 9

    nonisolated static let fallback = GateWordPlugConfig(
        weight: 1,
        wordCountMin: 3,
        wordCountMax: 6,
        words: WordCatalog.fallback.words,
        graphemes: GraphemeCatalog.fallback.graphemes,
        music: "gate"
    )

    nonisolated init(
        weight: Double = 1,
        wordCountMin: Int = 3,
        wordCountMax: Int = 6,
        letterPosition: GateWordPlugLetterPosition = .starting,
        fx: SoundEffectTable = SoundEffectTable(),
        words: [GateWord],
        graphemes: [GateGrapheme],
        vocabulary: LevelVocabularyPool? = nil,
        music: String? = nil
    ) {
        self.weight = weight
        self.wordCountMin = wordCountMin
        self.wordCountMax = wordCountMax
        self.letterPosition = letterPosition
        self.fx = fx
        self.words = GateWord.normalized(words)
        self.graphemes = GateGraphemeMatchConfig.normalizedGraphemes(graphemes)
        self.vocabulary = vocabulary ?? LevelVocabularyPool.singleTier(
            words: self.words,
            graphemes: self.graphemes
        )
        self.music = music
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
        graphemes = GateGraphemeMatchConfig.normalizedGraphemes(pool.allGraphemes)
    }

    func validate() throws {
        guard wordCountMin >= 1,
              wordCountMax >= wordCountMin,
              wordCountMax <= Self.maxWordsPerRound else {
            throw WorldSeedError.invalidGateWordPlugWordCountRange(
                min: wordCountMin,
                max: wordCountMax
            )
        }
        guard words.count >= wordCountMax else { throw WorldSeedError.invalidGateWords }
        guard !graphemes.isEmpty else { throw WorldSeedError.invalidGateWordPlugGraphemes }
        let known = Set(graphemes.map(\.grapheme))
        for entry in words {
            if letterPosition == .ending, entry.graphemes.count < 2 {
                throw WorldSeedError.invalidGateWordPlugGraphemes
            }
            guard let answer = letterPosition.answerGrapheme(in: entry),
                  known.contains(answer) else {
                throw WorldSeedError.invalidGateWordPlugGraphemes
            }
        }
    }
}

/// Discriminator for which gate puzzle a tile/strip runs. YAML raw values match minigame `type:`.
nonisolated enum GateMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    case soundOutWord = "sound-out-word-gate"
    case graphemeMatch = "grapheme-sound-gate"
    case wordPlug = "starting-sound-gate"
    case endingSoundPlug = "ending-sound-gate"
}

/// Gate kind + pick weight used during generation.
nonisolated struct WeightedGateKind: Equatable, Sendable {
    var kind: GateMinigameKind
    var weight: Double
}

/// Discriminated union over the gate minigame entries in level YAML.
nonisolated enum GateMinigameConfig: Equatable, Sendable {
    case soundOutWord(GateSoundOutWordConfig)
    case graphemeMatch(GateGraphemeMatchConfig)
    case wordPlug(GateWordPlugConfig)

    var kind: GateMinigameKind {
        switch self {
        case .soundOutWord: .soundOutWord
        case .graphemeMatch: .graphemeMatch
        // Both word-plug YAML types share this case; the mode picks the kind.
        case .wordPlug(let config): config.letterPosition == .ending ? .endingSoundPlug : .wordPlug
        }
    }

    /// Relative pick weight; negatives are rejected by `GateConfig.validate()`.
    var weight: Double {
        switch self {
        case .soundOutWord(let config): config.weight
        case .graphemeMatch(let config): config.weight
        case .wordPlug(let config): config.weight
        }
    }

    var music: String? {
        switch self {
        case .soundOutWord(let c): c.music
        case .graphemeMatch(let c): c.music
        case .wordPlug(let c): c.music
        }
    }
}

/// Resolved gate host config from level YAML `gate:`.
nonisolated struct GateConfig: Equatable, Sendable {
    /// Must include `"opened"` — the world-level gate-open SFX.
    var fx: SoundEffectTable
    /// Music track basename for gate minigames; `nil` → inherit from audio.yaml.
    var music: String?
    /// Probability of presenting a minigame on gate contact (`0...1`). Miss → free-open.
    var minigameChance: Double
    var minigames: [GateMinigameConfig]

    nonisolated static let fallback = GateConfig(
        fx: SoundEffectTable(events: ["opened": "gate-open"]),
        music: "gate",
        minigames: [
            .soundOutWord(.fallback),
            .graphemeMatch(.fallback),
        ],
        minigameChance: 0.6
    )

    nonisolated init(
        fx: SoundEffectTable,
        music: String? = nil,
        minigames: [GateMinigameConfig],
        minigameChance: Double = 0.6
    ) {
        self.fx = fx
        self.music = music
        self.minigameChance = minigameChance
        self.minigames = minigames
    }

    func validate() throws {
        guard fx.trackID(for: "opened") != nil else {
            throw WorldSeedError.invalidGateWords
        }
        guard minigameChance >= 0, minigameChance <= 1 else {
            throw WorldSeedError.invalidGateMinigameChance(minigameChance)
        }
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("gate.minigames must not be empty")
        }
        for minigame in minigames {
            guard minigame.weight >= 0 else {
                throw WorldSeedError.invalidGateMinigameWeight(minigame.weight)
            }
            switch minigame {
            case .soundOutWord(let c): try c.validate()
            case .graphemeMatch(let c): try c.validate()
            case .wordPlug(let c): try c.validate()
            }
        }
        var seenKinds = Set<GateMinigameKind>()
        for minigame in minigames {
            guard seenKinds.insert(minigame.kind).inserted else {
                throw WorldSeedError.duplicateGateMinigameKind(minigame.kind)
            }
        }
    }

    /// Gate kinds with their pick weights, in declaration order.
    /// Duplicate kinds are rejected by `validate()`, so this is 1:1 with `minigames`.
    var weightedMinigameKinds: [WeightedGateKind] {
        minigames.map { WeightedGateKind(kind: $0.kind, weight: $0.weight) }
    }

    func minigame(for kind: GateMinigameKind) -> GateMinigameConfig? {
        minigames.first { $0.kind == kind }
    }

    mutating func resolveMinigames(from pool: LevelVocabularyPool) throws {
        for i in minigames.indices {
            switch minigames[i] {
            case .soundOutWord(var config):
                try config.resolve(from: pool)
                minigames[i] = .soundOutWord(config)
            case .graphemeMatch(var config):
                try config.resolve(from: pool)
                minigames[i] = .graphemeMatch(config)
            case .wordPlug(var config):
                try config.resolve(from: pool)
                minigames[i] = .wordPlug(config)
            }
        }
    }
}
