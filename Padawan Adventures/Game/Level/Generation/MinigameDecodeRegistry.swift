import Foundation

/// Weighted random selection shared by combat and pit minigame pools.
nonisolated enum WeightedPicker {
    /// Entries with weight 0 are never chosen unless every weight is 0,
    /// in which case the first entry wins.
    static func pick<T>(
        from entries: [T],
        weight: (T) -> Double,
        using rng: inout some RandomNumberGenerator
    ) -> T? {
        guard !entries.isEmpty else { return nil }
        let total = entries.reduce(0.0) { partial, entry in
            partial + max(weight(entry), 0)
        }
        guard total > 0 else { return entries[0] }
        var roll = Double.random(in: 0..<total, using: &rng)
        for entry in entries {
            roll -= max(weight(entry), 0)
            if roll < 0 { return entry }
        }
        return entries[entries.count - 1]
    }
}

// MARK: - Gate

nonisolated struct GateMinigameDTO: Decodable {
    var type: String
    var fx: SoundEffectTable?
    var music: String?
    var numPaddingLetters: Int?
    var words: [String]?
    var incorrectReplayDelaySeconds: Double?
    var letterCountMin: Int?
    var letterCountMax: Int?
    var letters: [String]?
    var wordCountMin: Int?
    var wordCountMax: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case fx
        case music
        case numPaddingLetters = "num_padding_letters"
        case words
        case incorrectReplayDelaySeconds = "incorrect_replay_delay_seconds"
        case letterCountMin = "letter_count_min"
        case letterCountMax = "letter_count_max"
        case letters
        case wordCountMin = "word_count_min"
        case wordCountMax = "word_count_max"
    }
}

nonisolated enum MinigameDecodeRegistry {
    static func decodeGateMinigame(from entry: GateMinigameDTO) throws -> GateMinigameConfig {
        switch entry.type {
        case "spelling":
            return .spelling(GateSpellingConfig(
                fx: entry.fx ?? SoundEffectTable(),
                numPaddingLetters: entry.numPaddingLetters
                    ?? GateSpellingConfig.fallback.numPaddingLetters,
                wordIDs: entry.words?.map { $0.lowercased() },
                words: [],
                music: entry.music
            ))
        case "letter_match":
            return .letterMatch(GateLetterMatchConfig(
                incorrectReplayDelaySeconds: entry.incorrectReplayDelaySeconds
                    ?? GateLetterMatchConfig.fallback.incorrectReplayDelaySeconds,
                letterCountMin: entry.letterCountMin
                    ?? GateLetterMatchConfig.fallback.letterCountMin,
                letterCountMax: entry.letterCountMax
                    ?? GateLetterMatchConfig.fallback.letterCountMax,
                fx: entry.fx ?? SoundEffectTable(),
                letterIDs: entry.letters?.map { $0.lowercased() },
                letters: [],
                music: entry.music
            ))
        case "word_plug":
            return .wordPlug(GateWordPlugConfig(
                wordCountMin: entry.wordCountMin ?? GateWordPlugConfig.fallback.wordCountMin,
                wordCountMax: entry.wordCountMax ?? GateWordPlugConfig.fallback.wordCountMax,
                fx: entry.fx ?? SoundEffectTable(),
                wordIDs: entry.words?.map { $0.lowercased() },
                words: [],
                letters: [],
                music: entry.music
            ))
        default:
            throw WorldSeedError.decodeFailed(
                "Unknown gate minigame type: '\(entry.type)'"
            )
        }
    }

    // MARK: - Combat

    static func decodeCombatMinigame(from entry: CombatMinigameDTO) throws -> CombatMinigameConfig {
        switch entry.type {
        case CombatMinigameKind.slash.rawValue:
            return .slash(CombatSlashConfig(weight: entry.weight ?? 1))
        case CombatMinigameKind.deflect.rawValue:
            return .deflect(CombatDeflectConfig(
                weight: entry.weight ?? 1,
                monsterHP: entry.monsterHP ?? CombatDeflectConfig.defaultMonsterHP,
                orbTravelSeconds: entry.orbTravelSeconds
                    ?? CombatDeflectConfig.defaultOrbTravelSeconds,
                letterIDs: entry.letters?.map { $0.lowercased() },
                letters: []
            ))
        default:
            throw WorldSeedError.decodeFailed(
                "Unknown combat minigame type: '\(entry.type)'"
            )
        }
    }

    // MARK: - Pit

    static func decodePitMinigame(from entry: PitMinigameDTO) throws -> PitMinigameConfig {
        switch entry.type {
        case PitMinigameKind.spelling.rawValue:
            return .spelling(PitPuzzleConfig(
                weight: entry.weight ?? 1,
                numPaddingLetters: entry.numPaddingLetters
                    ?? PitPuzzleConfig.fallback.numPaddingLetters,
                wordIDs: entry.words?.map { $0.lowercased() },
                words: []
            ))
        case PitMinigameKind.bridge.rawValue:
            return .bridge(PitBridgeConfig(
                weight: entry.weight ?? 1,
                minWords: entry.minWords ?? PitBridgeConfig.defaultMinWords,
                maxWords: entry.maxWords ?? PitBridgeConfig.defaultMaxWords,
                wordIDs: entry.words?.map { $0.lowercased() } ?? PitBridgeConfig.defaultWordIDs,
                words: []
            ))

        default:
            throw WorldSeedError.decodeFailed("Unknown pit minigame type: '\(entry.type)'")
        }
    }
}

nonisolated struct CombatMinigameDTO: Decodable {
    var type: String
    var weight: Double?
    var monsterHP: Int?
    var orbTravelSeconds: Double?
    var letters: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case weight
        case monsterHP = "monster_hp"
        case orbTravelSeconds = "orb_travel_seconds"
        case letters
    }
}

nonisolated struct PitMinigameDTO: Decodable {
    var type: String
    var weight: Double?
    var numPaddingLetters: Int?
    /// Catalog ids for `spelling`, plain words for `bridge`.
    var words: [String]?
    var minWords: Int?
    var maxWords: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case weight
        case numPaddingLetters = "num_padding_letters"
        case words
        case minWords = "min_words"
        case maxWords = "max_words"
    }
}
