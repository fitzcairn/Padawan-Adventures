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
    var graphemeCountMin: Int?
    var graphemeCountMax: Int?
    var wordCountMin: Int?
    var wordCountMax: Int?
    var choiceCountMin: Int?
    var choiceCountMax: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case weight
        case fx
        case music
        case graphemeCountMin = "min_grapheme_count"
        case graphemeCountMax = "max_grapheme_count"
        case wordCountMin = "min_word_count"
        case wordCountMax = "max_word_count"
        case choiceCountMin = "min_choice_count"
        case choiceCountMax = "max_choice_count"
    }
}

nonisolated enum MinigameDecodeRegistry {
    static func decodeGateMinigame(from entry: GateMinigameDTO) throws -> GateMinigameConfig {
        switch entry.type {
        case GateMinigameKind.soundOutWord.rawValue:
            return .soundOutWord(GateSoundOutWordConfig(
                weight: entry.weight ?? 1,
                fx: entry.fx ?? SoundEffectTable(),
                choiceCountMin: entry.choiceCountMin
                    ?? GateSoundOutWordConfig.fallback.choiceCountMin,
                choiceCountMax: entry.choiceCountMax
                    ?? GateSoundOutWordConfig.fallback.choiceCountMax,
                words: [],
                graphemes: [],
                music: entry.music
            ))
        case GateMinigameKind.graphemeMatch.rawValue:
            return .graphemeMatch(GateGraphemeMatchConfig(
                weight: entry.weight ?? 1,
                graphemeCountMin: entry.graphemeCountMin
                    ?? GateGraphemeMatchConfig.fallback.graphemeCountMin,
                graphemeCountMax: entry.graphemeCountMax
                    ?? GateGraphemeMatchConfig.fallback.graphemeCountMax,
                fx: entry.fx ?? SoundEffectTable(),
                graphemes: [],
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
            words: [],
            graphemes: [],
            music: entry.music
        )
    }

    // MARK: - Combat

    static func decodeCombatMinigame(from entry: CombatMinigameDTO) throws -> CombatMinigameConfig {
        switch entry.type {
        case CombatMinigameKind.slash.rawValue:
            var graphemeCase: CombatGraphemeCase = .upper
            if let rawCase = entry.graphemeCase {
                let trimmed = rawCase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let parsed = CombatGraphemeCase(rawValue: trimmed) else {
                    throw WorldSeedError.invalidCombatGraphemeCase(rawCase)
                }
                graphemeCase = parsed
            }
            return .slash(CombatSlashConfig(
                weight: entry.weight ?? 1,
                minDecoyCount: entry.minDecoyCount
                    ?? CombatMinigameEngine.Config.defaultMinDecoyCount,
                maxDecoyCount: entry.maxDecoyCount
                    ?? CombatMinigameEngine.Config.defaultMaxDecoyCount,
                graphemeCase: graphemeCase,
                graphemeSoundRepeatSeconds: entry.graphemeSoundRepeatSeconds ?? 3
            ))
        case CombatMinigameKind.startingSoundDeflect.rawValue:
            return .deflect(Self.combatDeflectConfig(from: entry, letterPosition: .starting))
        case CombatMinigameKind.endingSoundDeflect.rawValue:
            return .deflect(Self.combatDeflectConfig(from: entry, letterPosition: .ending))
        default:
            throw WorldSeedError.decodeFailed(
                "Unknown combat minigame type: '\(entry.type)'"
            )
        }
    }

    private static func combatDeflectConfig(
        from entry: CombatMinigameDTO,
        letterPosition: GateWordPlugLetterPosition
    ) -> CombatDeflectConfig {
        CombatDeflectConfig(
            weight: entry.weight ?? 1,
            monsterHP: entry.monsterHP ?? CombatDeflectConfig.defaultMonsterHP,
            orbTravelSeconds: entry.orbTravelSeconds
                ?? CombatDeflectConfig.defaultOrbTravelSeconds,
            letterPosition: letterPosition,
            ringCount: entry.ringCount ?? CombatDeflectConfig.defaultRingCount,
            graphemes: []
        )
    }

    // MARK: - Pit

    static func decodePitMinigame(from entry: PitMinigameDTO) throws -> PitMinigameConfig {
        switch entry.type {
        case PitMinigameKind.soundOutWord.rawValue:
            return .soundOutWord(PitSoundOutWordConfig(
                weight: entry.weight ?? 1,
                choiceCountMin: entry.choiceCountMin
                    ?? PitSoundOutWordConfig.fallback.choiceCountMin,
                choiceCountMax: entry.choiceCountMax
                    ?? PitSoundOutWordConfig.fallback.choiceCountMax,
                words: [],
                graphemes: []
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
            words: []
        )
    }
}

nonisolated struct CombatMinigameDTO: Decodable {
    var type: String
    var weight: Double?
    var monsterHP: Int?
    var orbTravelSeconds: Double?
    var ringCount: Int?
    var minDecoyCount: Int?
    var maxDecoyCount: Int?
    var graphemeCase: String?
    var graphemeSoundRepeatSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case weight
        case monsterHP = "monster_hit_points"
        case orbTravelSeconds = "orb_travel_seconds"
        case ringCount = "ring_count"
        case minDecoyCount = "min_decoy_count"
        case maxDecoyCount = "max_decoy_count"
        case graphemeCase = "grapheme_case"
        case graphemeSoundRepeatSeconds = "grapheme_sound_repeat_seconds"
    }
}

nonisolated struct PitMinigameDTO: Decodable {
    var type: String
    var weight: Double?
    var choiceCountMin: Int?
    var choiceCountMax: Int?
    var minWords: Int?
    var maxWords: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case weight
        case choiceCountMin = "min_choice_count"
        case choiceCountMax = "max_choice_count"
        case minWords = "min_word_count"
        case maxWords = "max_word_count"
    }
}
