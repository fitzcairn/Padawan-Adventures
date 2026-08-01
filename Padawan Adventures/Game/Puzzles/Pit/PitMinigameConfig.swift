import Foundation

/// Discriminator for which pit minigame a pit contact runs. Raw values match YAML `type:`.
nonisolated enum PitMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    /// The original hop-the-letters spelling puzzle (`PitScene`).
    case spelling
    /// Drag lettered floor tiles into slots to bridge the pit (`PitBridgeScene`).
    case bridge
}

/// Per-entry config for the bridge-building pit game.
/// `words` are plain words, not `words.yaml` ids: every prompt is synthesized, so no
/// `sfx_word_*` assets are required.
nonisolated struct PitBridgeConfig: Equatable, Sendable {
    var weight: Double
    /// Inclusive lower bound on words (and therefore bridge tiles) per session.
    var minWords: Int
    /// Inclusive upper bound on words per session; the pool must be at least this large.
    var maxWords: Int
    var words: [String]

    static let defaultMinWords = 2
    static let defaultMaxWords = 4
    static let defaultWords = ["open", "start", "dog", "man", "bat", "kam"]

    nonisolated static let fallback = PitBridgeConfig(weight: 1)

    nonisolated init(
        weight: Double = 1,
        minWords: Int = defaultMinWords,
        maxWords: Int = defaultMaxWords,
        words: [String] = defaultWords
    ) {
        self.weight = weight
        self.minWords = minWords
        self.maxWords = maxWords
        self.words = words.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for word in words {
            guard word.count >= 2,
                  word.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  seen.insert(word).inserted else {
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
        case .bridge: .bridge
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
    var minigames: [PitMinigameConfig]

    /// Used when a level omits `pit:` entirely — spelling only, preserving old behaviour.
    nonisolated static let fallback = PitConfig(
        fx: SoundEffectTable(events: [
            "lose": "pit-falling",
            "jump": "pit-jump",
        ]),
        minigames: [.spelling(.fallback)]
    )

    nonisolated init(fx: SoundEffectTable, minigames: [PitMinigameConfig]) {
        self.fx = fx
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
        let total = minigames.reduce(0.0) { $0 + max($1.weight, 0) }
        guard total > 0 else { return minigames[0] }
        var roll = Double.random(in: 0..<total, using: &rng)
        for entry in minigames {
            roll -= max(entry.weight, 0)
            if roll < 0 { return entry }
        }
        return minigames[minigames.count - 1]
    }

    mutating func resolveWords(from catalog: WordCatalog) throws {
        for index in minigames.indices {
            if case .spelling(var config) = minigames[index] {
                try config.resolveWords(from: catalog)
                minigames[index] = .spelling(config)
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
