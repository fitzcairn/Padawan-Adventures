import Foundation

/// Per-entry gate sound-out-word config: sound out the prompted word one letter at a time,
/// dragging the right capacitor out of each offered set.
/// Vocabulary lives in shared `Resources/Config/Catalogs/words.yaml`; levels may optionally
/// subset via `words: [id, …]`. Letters always come from the full `Catalogs/graphemes.yaml`,
/// which supplies the name/pronunciation audio and the decoy pool.
nonisolated struct GateSoundOutWordConfig: Equatable, Sendable {
    /// Relative pick weight within `gate.minigames`.
    var weight: Double
    /// In-puzzle FX (optional `win` override for shared `sound.yaml`).
    var fx: SoundEffectTable
    /// Inclusive lower bound on capacitors offered per letter.
    var choiceCountMin: Int
    /// Inclusive upper bound on capacitors offered per letter.
    var choiceCountMax: Int
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]
    /// Resolved full letter catalog. Populated via `resolveLetters(from:)`.
    var letters: [GateLetter]
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
        letters: LetterCatalog.fallback.letters,
        music: "gate"
    )

    nonisolated init(
        weight: Double = 1,
        fx: SoundEffectTable = SoundEffectTable(),
        choiceCountMin: Int = 2,
        choiceCountMax: Int = 4,
        wordIDs: [String]? = nil,
        words: [GateWord],
        letters: [GateLetter],
        music: String? = nil
    ) {
        self.weight = weight
        self.fx = fx
        self.choiceCountMin = choiceCountMin
        self.choiceCountMax = choiceCountMax
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = GateWord.normalized(words)
        self.letters = GateLetterMatchConfig.normalizedLetters(letters)
        self.music = music
    }

    mutating func resolveWords(from catalog: WordCatalog) throws {
        words = try catalog.resolve(ids: wordIDs)
    }

    mutating func resolveLetters(from catalog: LetterCatalog) throws {
        letters = try catalog.resolve(ids: nil)
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
        // Every letter is spoken by name and by sound, so all of them need grapheme audio.
        let known = Set(letters.map(\.letter))
        guard known.count >= choiceCountMax else {
            throw WorldSeedError.invalidGateSoundOutWordLetters
        }
        for entry in words {
            for character in entry.word {
                guard known.contains(String(character).lowercased()) else {
                    throw WorldSeedError.invalidGateSoundOutWordLetters
                }
            }
        }
    }
}
/// A gate letter-match puzzle letter: glyph + pronunciation/name track basenames.
nonisolated struct GateLetter: Equatable, Sendable {
    var letter: String
    var pronunciation: String
    var name: String
}

/// Per-entry gate letter-matching config.
/// Letter FX lives in shared `Resources/Config/Catalogs/graphemes.yaml`; levels may optionally subset via `graphemes: [id, …]`.
nonisolated struct GateLetterMatchConfig: Equatable, Sendable {
    /// Relative pick weight within `gate.minigames`.
    var weight: Double
    /// Inclusive lower bound for letters chosen per round (clamped to the letter pool).
    var letterCountMin: Int
    /// Inclusive upper bound for letters chosen per round (clamped to the letter pool).
    var letterCountMax: Int
    /// In-puzzle FX (optional `correct` override for shared `sound.yaml`).
    var fx: SoundEffectTable
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var letterIDs: [String]?
    /// Resolved letters (sorted). Populated via `resolveLetters(from:)`.
    var letters: [GateLetter]
    /// Per-entry music override; `nil` → use `gate.music`.
    var music: String?

    nonisolated static let fallback = GateLetterMatchConfig(
        weight: 1,
        letterCountMin: 4,
        letterCountMax: 8,
        letters: LetterCatalog.fallback.letters,
        music: "gate"
    )

    nonisolated init(
        weight: Double = 1,
        letterCountMin: Int = 4,
        letterCountMax: Int = 8,
        fx: SoundEffectTable = SoundEffectTable(),
        letterIDs: [String]? = nil,
        letters: [GateLetter],
        music: String? = nil
    ) {
        self.weight = weight
        self.letterCountMin = letterCountMin
        self.letterCountMax = letterCountMax
        self.fx = fx
        self.letterIDs = letterIDs?.map { $0.lowercased() }
        self.letters = Self.normalizedLetters(letters)
        self.music = music
    }

    mutating func resolveLetters(from catalog: LetterCatalog) throws {
        letters = try catalog.resolve(ids: letterIDs)
    }

    func validate() throws {
        guard letterCountMin >= 1, letterCountMax >= letterCountMin else {
            throw WorldSeedError.invalidGateLetterMatchLetterCountRange(
                min: letterCountMin,
                max: letterCountMax
            )
        }
        guard !letters.isEmpty else {
            throw WorldSeedError.invalidGateLetterMatchLetters
        }
        try CatalogValidators.validateLetterEntries(
            letters,
            requirePronunciation: true,
            emptyError: .invalidGateLetterMatchLetters,
            invalidEntryError: .invalidGateLetterMatchLetters
        )
    }

    static func normalizedLetters(_ letters: [GateLetter]) -> [GateLetter] {
        letters
            .map {
                GateLetter(
                    letter: $0.letter.lowercased(),
                    pronunciation: $0.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .sorted { $0.letter < $1.letter }
    }
}

/// Which letter of the word the player must plug in.
nonisolated enum GateWordPlugLetterPosition: String, Equatable, Sendable {
    case starting
    case ending

    /// Lowercased answer letter; `nil` for an empty word.
    func answerLetter(in word: String) -> String? {
        switch self {
        case .starting: word.first.map { String($0).lowercased() }
        case .ending: word.last.map { String($0).lowercased() }
        }
    }

    /// Console mask with the answer letter blanked: `_og` for starting, `do_` for ending.
    func maskedText(for word: String) -> String {
        switch self {
        case .starting: "_\(word.dropFirst())"
        case .ending: "\(word.dropLast())_"
        }
    }
}

/// Per-entry gate word-plug config: match each word's missing first or last letter (see `letterPosition`).
/// Words come from `Catalogs/words.yaml`; letters always come from the full `Catalogs/graphemes.yaml`.
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
    /// Optional subset of shared word-catalog ids (`nil` = full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]
    /// Resolved full letter catalog. Populated via `resolveLetters(from:)`.
    var letters: [GateLetter]
    /// Per-entry music override; `nil` → use `gate.music`.
    var music: String?

    /// Up to 3 columns x 3 rows of word plates.
    nonisolated static let maxWordsPerRound = 9

    nonisolated static let fallback = GateWordPlugConfig(
        weight: 1,
        wordCountMin: 3,
        wordCountMax: 6,
        words: WordCatalog.fallback.words,
        letters: LetterCatalog.fallback.letters,
        music: "gate"
    )

    nonisolated init(
        weight: Double = 1,
        wordCountMin: Int = 3,
        wordCountMax: Int = 6,
        letterPosition: GateWordPlugLetterPosition = .starting,
        fx: SoundEffectTable = SoundEffectTable(),
        wordIDs: [String]? = nil,
        words: [GateWord],
        letters: [GateLetter],
        music: String? = nil
    ) {
        self.weight = weight
        self.wordCountMin = wordCountMin
        self.wordCountMax = wordCountMax
        self.letterPosition = letterPosition
        self.fx = fx
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = GateSpellingConfig.normalizedWords(words)
        self.letters = GateLetterMatchConfig.normalizedLetters(letters)
        self.music = music
    }

    mutating func resolveWords(from catalog: WordCatalog) throws {
        words = try catalog.resolve(ids: wordIDs)
    }

    mutating func resolveLetters(from catalog: LetterCatalog) throws {
        letters = try catalog.resolve(ids: nil)
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
        guard !words.isEmpty else { throw WorldSeedError.invalidGateWords }
        guard !letters.isEmpty else { throw WorldSeedError.invalidGateWordPlugLetters }
        // The answer letter must have name + pronunciation audio in graphemes.yaml.
        let known = Set(letters.map(\.letter))
        for entry in words {
            if letterPosition == .ending, entry.word.count < 2 {
                throw WorldSeedError.invalidGateWordPlugLetters
            }
            guard let answer = letterPosition.answerLetter(in: entry.word),
                  known.contains(answer) else {
                throw WorldSeedError.invalidGateWordPlugLetters
            }
        }
    }
}

/// Discriminator for which gate puzzle a tile/strip runs. YAML raw values match minigame `type:`.
nonisolated enum GateMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    case spelling = "spelling-image-gate"
    case letterMatch = "grapheme-sound-gate"
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
    case spelling(GateSpellingConfig)
    case letterMatch(GateLetterMatchConfig)
    case wordPlug(GateWordPlugConfig)

    var kind: GateMinigameKind {
        switch self {
        case .spelling: .spelling
        case .letterMatch: .letterMatch
        // Both word-plug YAML types share this case; the mode picks the kind.
        case .wordPlug(let config): config.letterPosition == .ending ? .endingSoundPlug : .wordPlug
        }
    }

    /// Relative pick weight; negatives are rejected by `GateConfig.validate()`.
    var weight: Double {
        switch self {
        case .spelling(let config): config.weight
        case .letterMatch(let config): config.weight
        case .wordPlug(let config): config.weight
        }
    }

    var music: String? {
        switch self {
        case .spelling(let c): c.music
        case .letterMatch(let c): c.music
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
            .spelling(.fallback),
            .letterMatch(.fallback),
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
            case .spelling(let c): try c.validate()
            case .letterMatch(let c): try c.validate()
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

    mutating func resolveMinigames(
        wordCatalog: WordCatalog,
        letterCatalog: LetterCatalog
    ) throws {
        for i in minigames.indices {
            switch minigames[i] {
            case .spelling(var config):
                try config.resolveWords(from: wordCatalog)
                minigames[i] = .spelling(config)
            case .letterMatch(var config):
                try config.resolveLetters(from: letterCatalog)
                minigames[i] = .letterMatch(config)
            case .wordPlug(var config):
                try config.resolveWords(from: wordCatalog)
                try config.resolveLetters(from: letterCatalog)
                minigames[i] = .wordPlug(config)
            }
        }
    }
}
