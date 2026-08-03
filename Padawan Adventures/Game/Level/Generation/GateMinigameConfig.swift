import Foundation

/// Per-entry gate spelling-puzzle config (was `GatePuzzleConfig`).
/// Vocabulary lives in shared `Resources/Config/Vocab/words.yaml`; levels may optionally subset via `words: [id, …]`.
nonisolated struct GateSpellingConfig: Equatable, Sendable {
    /// In-puzzle FX (optional `win` override for shared `sound.yaml`).
    var fx: SoundEffectTable
    /// Extra random letters beyond the chosen word (total sprites = word length + this).
    var numPaddingLetters: Int
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]
    /// Per-entry music override; `nil` → use `game_music.gate`.
    var music: String?

    nonisolated static let fallback = GateSpellingConfig(
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words,
        music: "gate"
    )

    nonisolated init(
        fx: SoundEffectTable = SoundEffectTable(),
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord],
        music: String? = nil
    ) {
        self.fx = fx
        self.numPaddingLetters = numPaddingLetters
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = Self.normalizedWords(words)
        self.music = music
    }

    mutating func resolveWords(from catalog: WordCatalog) throws {
        words = try catalog.resolve(ids: wordIDs)
    }

    func validate() throws {
        guard numPaddingLetters >= 0 else {
            throw WorldSeedError.invalidGatePaddingLetters(numPaddingLetters)
        }
        try CatalogValidators.validateWordEntries(
            words,
            emptyError: .invalidGateWords,
            invalidEntryError: .invalidGateWords
        )
    }

    static func normalizedWords(_ words: [GateWord]) -> [GateWord] {
        words
            .map { entry in
                var progressive: [String: String] = [:]
                for (key, value) in entry.progressive {
                    progressive[key.lowercased()] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let image = entry.image?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return GateWord(
                    word: entry.word.lowercased(),
                    image: (image?.isEmpty == false) ? image : nil,
                    sfx: entry.sfx.trimmingCharacters(in: .whitespacesAndNewlines),
                    progressive: progressive
                )
            }
            .sorted { $0.word < $1.word }
    }
}
/// A gate letter-match puzzle letter: glyph + pronunciation/name track basenames.
nonisolated struct GateLetter: Equatable, Sendable {
    var letter: String
    var pronunciation: String
    var name: String
}

/// Per-entry gate letter-matching config.
/// Letter FX lives in shared `Resources/Config/Catalogs/phonics.yaml`; levels may optionally subset via `letters: [id, …]`.
nonisolated struct GateLetterMatchConfig: Equatable, Sendable {
    /// Seconds after an incorrect tap before replaying the target pronunciation.
    var incorrectReplayDelaySeconds: Double
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
    /// Per-entry music override; `nil` → use `game_music.gate`.
    var music: String?

    nonisolated static let fallback = GateLetterMatchConfig(
        incorrectReplayDelaySeconds: 1,
        letterCountMin: 4,
        letterCountMax: 8,
        letters: LetterCatalog.fallback.letters,
        music: "gate"
    )

    nonisolated init(
        incorrectReplayDelaySeconds: Double = 1,
        letterCountMin: Int = 4,
        letterCountMax: Int = 8,
        fx: SoundEffectTable = SoundEffectTable(),
        letterIDs: [String]? = nil,
        letters: [GateLetter],
        music: String? = nil
    ) {
        self.incorrectReplayDelaySeconds = incorrectReplayDelaySeconds
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
        guard incorrectReplayDelaySeconds > 0 else {
            throw WorldSeedError.invalidGateLetterMatchIncorrectReplayDelay(incorrectReplayDelaySeconds)
        }
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

/// Per-entry gate word-plug config: match each word's missing first letter.
/// Words come from `Catalogs/words.yaml`; letters always come from the full `Catalogs/phonics.yaml`.
nonisolated struct GateWordPlugConfig: Equatable, Sendable {
    /// Inclusive lower bound for words per round (>= 1).
    var wordCountMin: Int
    /// Inclusive upper bound for words per round (<= `maxWordsPerRound`).
    var wordCountMax: Int
    var fx: SoundEffectTable
    /// Optional subset of shared word-catalog ids (`nil` = full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]
    /// Resolved full letter catalog. Populated via `resolveLetters(from:)`.
    var letters: [GateLetter]
    /// Per-entry music override; `nil` → use `game_music.gate`.
    var music: String?

    /// Up to 3 columns x 3 rows of word plates.
    nonisolated static let maxWordsPerRound = 9

    nonisolated static let fallback = GateWordPlugConfig(
        wordCountMin: 3,
        wordCountMax: 6,
        words: WordCatalog.fallback.words,
        letters: LetterCatalog.fallback.letters,
        music: "gate"
    )

    nonisolated init(
        wordCountMin: Int = 3,
        wordCountMax: Int = 6,
        fx: SoundEffectTable = SoundEffectTable(),
        wordIDs: [String]? = nil,
        words: [GateWord],
        letters: [GateLetter],
        music: String? = nil
    ) {
        self.wordCountMin = wordCountMin
        self.wordCountMax = wordCountMax
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
        // Every word's first letter must have name + pronunciation audio.
        let known = Set(letters.map(\.letter))
        for entry in words {
            guard let first = entry.word.first,
                  known.contains(String(first).lowercased()) else {
                throw WorldSeedError.invalidGateWordPlugLetters
            }
        }
    }
}

/// Discriminator for which gate puzzle a tile/strip runs. YAML raw values match minigame `type:`.
nonisolated enum GateMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    case spelling
    case letterMatch = "letter_match"
    case wordPlug = "word_plug"
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
        case .wordPlug: .wordPlug
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
    /// Probability of presenting a minigame on gate contact (`0...1`). Miss → free-open.
    var minigameChance: Double
    var minigames: [GateMinigameConfig]

    nonisolated static let fallback = GateConfig(
        fx: SoundEffectTable(events: ["opened": "gate-open"]),
        minigames: [
            .spelling(.fallback),
            .letterMatch(.fallback),
        ],
        minigameChance: 0.6
    )

    nonisolated init(
        fx: SoundEffectTable,
        minigames: [GateMinigameConfig],
        minigameChance: Double = 0.6
    ) {
        self.fx = fx
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
            switch minigame {
            case .spelling(let c): try c.validate()
            case .letterMatch(let c): try c.validate()
            case .wordPlug(let c): try c.validate()
            }
        }
    }

    /// Unique kinds in `minigames`, first-seen order.
    var distinctMinigameKinds: [GateMinigameKind] {
        var seen = Set<GateMinigameKind>()
        var ordered: [GateMinigameKind] = []
        for entry in minigames {
            if seen.insert(entry.kind).inserted {
                ordered.append(entry.kind)
            }
        }
        return ordered
    }

    func minigame(for kind: GateMinigameKind) -> GateMinigameConfig? {
        minigames.first { $0.kind == kind }
    }

    /// Uniform pick among distinct kinds (generation only).
    func pickMinigameKind(using rng: inout some RandomNumberGenerator) throws -> GateMinigameKind {
        let kinds = distinctMinigameKinds
        guard !kinds.isEmpty else {
            throw WorldSeedError.decodeFailed("gate.minigames must not be empty")
        }
        return kinds[Int.random(in: 0..<kinds.count, using: &rng)]
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
