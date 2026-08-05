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
    var weight: Double?
    var fx: SoundEffectTable?
    var music: String?
    var numPaddingLetters: Int?
    var words: [String]?
    var letterCountMin: Int?
    var letterCountMax: Int?
    var graphemes: [String]?
    var wordCountMin: Int?
    var wordCountMax: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case weight
        case fx
        case music
        case numPaddingLetters = "padding_grapheme_count"
        case words
        case letterCountMin = "min_grapheme_count"
        case letterCountMax = "max_grapheme_count"
        case graphemes
        case wordCountMin = "min_word_count"
        case wordCountMax = "max_word_count"
    }
}

nonisolated enum MinigameDecodeRegistry {
    static func decodeGateMinigame(from entry: GateMinigameDTO) throws -> GateMinigameConfig {
        switch entry.type {
        case GateMinigameKind.spelling.rawValue:
            return .spelling(GateSpellingConfig(
                weight: entry.weight ?? 1,
                fx: entry.fx ?? SoundEffectTable(),
                numPaddingLetters: entry.numPaddingLetters
                    ?? GateSpellingConfig.fallback.numPaddingLetters,
                wordIDs: entry.words?.map { $0.lowercased() },
                words: [],
                music: entry.music
            ))
        case GateMinigameKind.letterMatch.rawValue:
            return .letterMatch(GateLetterMatchConfig(
                weight: entry.weight ?? 1,
                letterCountMin: entry.letterCountMin
                    ?? GateLetterMatchConfig.fallback.letterCountMin,
                letterCountMax: entry.letterCountMax
                    ?? GateLetterMatchConfig.fallback.letterCountMax,
                fx: entry.fx ?? SoundEffectTable(),
                letterIDs: entry.graphemes?.map { $0.lowercased() },
                letters: [],
                music: entry.music
            ))
        case GateMinigameKind.wordPlug.rawValue:
            return .wordPlug(Self.gateWordPlugConfig(from: entry, letterPosition: .starting))
        case GateMinigameKind.endingSoundPlug.rawValue:
            return .wordPlug(Self.gateWordPlugConfig(from: entry, letterPosition: .ending))
        default:
            throw WorldSeedError.decodeFailed(
                "Unknown gate minigame type: '\(entry.type)'"
            )
        }
    }

    private static func gateWordPlugConfig(
        from entry: GateMinigameDTO,
        letterPosition: GateWordPlugLetterPosition
    ) -> GateWordPlugConfig {
        GateWordPlugConfig(
            weight: entry.weight ?? 1,
            wordCountMin: entry.wordCountMin ?? GateWordPlugConfig.fallback.wordCountMin,
            wordCountMax: entry.wordCountMax ?? GateWordPlugConfig.fallback.wordCountMax,
            letterPosition: letterPosition,
            fx: entry.fx ?? SoundEffectTable(),
            wordIDs: entry.words?.map { $0.lowercased() },
            words: [],
            letters: [],
            music: entry.music
        )
    }

    // MARK: - Combat

    static func decodeCombatMinigame(from entry: CombatMinigameDTO) throws -> CombatMinigameConfig {
        switch entry.type {
        case CombatMinigameKind.slash.rawValue:
            var letterCase: CombatLetterCase = .upper
            if let rawCase = entry.letterCase {
                let trimmed = rawCase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let parsed = CombatLetterCase(rawValue: trimmed) else {
                    throw WorldSeedError.invalidCombatLetterCase(rawCase)
                }
                letterCase = parsed
            }
            return .slash(CombatSlashConfig(
                weight: entry.weight ?? 1,
                letterSpawnMultiplier: entry.letterSpawnMultiplier ?? 1.0,
                letterCase: letterCase,
                letterSoundRepeatSeconds: entry.letterSoundRepeatSeconds ?? 3
            ))
        case CombatMinigameKind.deflect.rawValue:
            return .deflect(CombatDeflectConfig(
                weight: entry.weight ?? 1,
                monsterHP: entry.monsterHP ?? CombatDeflectConfig.defaultMonsterHP,
                orbTravelSeconds: entry.orbTravelSeconds
                    ?? CombatDeflectConfig.defaultOrbTravelSeconds,
                letterIDs: entry.graphemes?.map { $0.lowercased() },
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
            return .bridge(Self.pitBridgeConfig(from: entry, letterPosition: .ending))
        case PitMinigameKind.startingSoundBridge.rawValue:
            return .bridge(Self.pitBridgeConfig(from: entry, letterPosition: .starting))

        default:
            throw WorldSeedError.decodeFailed("Unknown pit minigame type: '\(entry.type)'")
        }
    }

    private static func pitBridgeConfig(
        from entry: PitMinigameDTO,
        letterPosition: GateWordPlugLetterPosition
    ) -> PitBridgeConfig {
        PitBridgeConfig(
            weight: entry.weight ?? 1,
            minWords: entry.minWords ?? PitBridgeConfig.defaultMinWords,
            maxWords: entry.maxWords ?? PitBridgeConfig.defaultMaxWords,
            letterPosition: letterPosition,
            wordIDs: entry.words?.map { $0.lowercased() } ?? PitBridgeConfig.defaultWordIDs,
            words: []
        )
    }
}

nonisolated struct CombatMinigameDTO: Decodable {
    var type: String
    var weight: Double?
    var monsterHP: Int?
    var orbTravelSeconds: Double?
    var graphemes: [String]?
    var letterSpawnMultiplier: Double?
    var letterCase: String?
    var letterSoundRepeatSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case weight
        case monsterHP = "monster_hit_points"
        case orbTravelSeconds = "orb_travel_seconds"
        case graphemes
        case letterSpawnMultiplier = "grapheme_spawn_multiplier"
        case letterCase = "grapheme_case"
        case letterSoundRepeatSeconds = "grapheme_sound_repeat_seconds"
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
        case numPaddingLetters = "padding_grapheme_count"
        case words
        case minWords = "min_word_count"
        case maxWords = "max_word_count"
    }
}
