import Foundation

/// Discriminator for which pit minigame a pit contact runs. Raw values match YAML `type:`.
nonisolated enum PitMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// The original hop-the-letters spelling puzzle (`PitScene`).
    case spelling = "spelling-image-pit"
    /// Drag lettered floor tiles into slots to bridge the pit (`PitBridgeScene`).
    case bridge = "ending-sound-pit"
    /// Same board, but the tile must match the word's first letter.
    case startingSoundBridge = "starting-sound-pit"
}

/// Per-entry config for the bridge-building pit game.
/// `words:` are shared catalog ids from `words.yaml` (must resolve to imaged entries).
nonisolated struct PitBridgeConfig: Equatable, Sendable {
    var weight: Double
    /// Inclusive lower bound on words (and therefore bridge tiles) per session.
    var minWords: Int
    /// Inclusive upper bound on words per session; the pool must be at least this large.
    var maxWords: Int
    /// Which letter the player supplies: word end (`ending-sound-pit`) or start (`starting-sound-pit`).
    var letterPosition: GateWordPlugGraphemePosition
    /// Optional subset of shared catalog ids (`nil` / omitted YAML → `defaultWordIDs`).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]

    static let defaultMinWords = 2
    static let defaultMaxWords = 4
    /// Catalog ids with illustrations — used when YAML omits `words:`.
    static let defaultWordIDs = ["car", "dog", "trash", "sun", "star", "book"]

    nonisolated static let fallback = PitBridgeConfig(
        weight: 1,
        wordIDs: defaultWordIDs,
        words: WordCatalog.fallback.words.filter { defaultWordIDs.contains($0.word) }
    )

    nonisolated init(
        weight: Double = 1,
        minWords: Int = defaultMinWords,
        maxWords: Int = defaultMaxWords,
        letterPosition: GateWordPlugGraphemePosition = .ending,
        wordIDs: [String]? = defaultWordIDs,
        words: [GateWord] = []
    ) {
        self.weight = weight
        self.minWords = minWords
        self.maxWords = maxWords
        self.letterPosition = letterPosition
        self.wordIDs = wordIDs?.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        self.words = GateWord.normalized(words)
    }

    mutating func resolveWords(from catalog: WordCatalog) throws {
        do {
            words = try catalog.resolve(ids: wordIDs)
        } catch WorldSeedError.invalidGateWords {
            throw WorldSeedError.invalidPitBridgeWords
        }
    }

    func validate() throws {
        guard minWords >= 1, maxWords >= minWords else {
            throw WorldSeedError.invalidPitBridgeWordRange(min: minWords, max: maxWords)
        }
        // A session picks up to `maxWords` distinct words, so the pool must cover it.
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
            guard entry.word.count >= 2,
                  let image = entry.image?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !image.isEmpty,
                  seen.insert(entry.word).inserted else {
                throw WorldSeedError.invalidPitBridgeWords
            }
        }
    }
}

/// Discriminated union over the pit minigame entries in level YAML.
nonisolated enum PitMinigameConfig: Equatable, Sendable {
    case spelling(PitPuzzleConfig)
    case bridge(PitBridgeConfig)

    var kind: PitMinigameKind {
        switch self {
        case .spelling: .spelling
        // Both bridge YAML types share this case; the mode picks the kind.
        case .bridge(let config):
            config.letterPosition == .starting ? .startingSoundBridge : .bridge
        }
    }

    /// Relative pick weight; negatives are rejected by `PitConfig.validate()`.
    var weight: Double {
        switch self {
        case .spelling(let config): config.weight
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

    /// Used when a level omits `pit:` entirely — spelling only, preserving old behaviour.
    nonisolated static let fallback = PitConfig(
        fx: SoundEffectTable(events: [
            "jump": "pit-jump",
        ]),
        music: "pit",
        minigames: [.spelling(.fallback)]
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

    mutating func resolveWords(from catalog: WordCatalog) throws {
        for index in minigames.indices {
            switch minigames[index] {
            case .spelling(var config):
                try config.resolveWords(from: catalog)
                minigames[index] = .spelling(config)
            case .bridge(var config):
                try config.resolveWords(from: catalog)
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
            case .spelling(let config): try config.validate()
            case .bridge(let config): try config.validate()
            }
        }
    }
}
