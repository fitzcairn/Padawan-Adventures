import Foundation

// MARK: - GateConfig Decodable (private DTO)

extension GateConfig {
    /// Decodes the `gate:` keyed block or falls back to `.fallback`.
    nonisolated init(
        from decoder: Decoder,
        container: KeyedDecodingContainer<LevelConfig.CodingKeys>
    ) throws {
        guard container.contains(.gate) else {
            self = .fallback
            return
        }
        let dto = try container.decode(GateConfigDTO.self, forKey: .gate)
        fx = dto.fx ?? SoundEffectTable(events: ["opened": "gate-open"])
        minigameChance = dto.minigameChance ?? 0.6
        guard let entries = dto.minigames, !entries.isEmpty else {
            throw WorldSeedError.decodeFailed("gate.minigames must not be empty")
        }
        minigames = try entries.map { entry in
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
    }
}

private nonisolated struct GateConfigDTO: Decodable {
    var fx: SoundEffectTable?
    var minigameChance: Double?
    var minigames: [GateMinigameDTO]?

    enum CodingKeys: String, CodingKey {
        case fx
        case minigameChance = "minigame_chance"
        case minigames
    }
}

private nonisolated struct GateMinigameDTO: Decodable {
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

// MARK: - CombatConfig Decodable (private DTO)

extension CombatConfig {
    /// Decodes the `combat:` keyed block or falls back to slash-only.
    nonisolated init(
        from decoder: Decoder,
        container: KeyedDecodingContainer<LevelConfig.CodingKeys>
    ) throws {
        guard container.contains(.combat) else {
            self = .fallback
            return
        }
        let dto = try container.decode(CombatConfigDTO.self, forKey: .combat)
        guard let entries = dto.minigames, !entries.isEmpty else {
            throw WorldSeedError.decodeFailed("combat.minigames must not be empty")
        }
        minigames = try entries.map { entry in
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
                    // Filled by `resolveLetters(from:)` after decode.
                    letters: []
                ))
            default:
                throw WorldSeedError.decodeFailed(
                    "Unknown combat minigame type: '\(entry.type)'"
                )
            }
        }
    }
}

private nonisolated struct CombatConfigDTO: Decodable {
    var minigames: [CombatMinigameDTO]?
}

private nonisolated struct CombatMinigameDTO: Decodable {
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

// MARK: - PitConfig Decodable (private DTO)

extension PitConfig {
    /// Decodes the `pit:` keyed block or falls back to spelling-only.
    nonisolated init(
        from decoder: Decoder,
        container: KeyedDecodingContainer<LevelConfig.CodingKeys>
    ) throws {
        guard container.contains(.pit) else {
            self = .fallback
            return
        }
        let dto = try container.decode(PitConfigDTO.self, forKey: .pit)
        fx = dto.fx ?? Self.fallback.fx
        guard let entries = dto.minigames, !entries.isEmpty else {
            throw WorldSeedError.decodeFailed("pit.minigames must not be empty")
        }
        minigames = try entries.map { entry in
            switch entry.type {
            case PitMinigameKind.spelling.rawValue:
                return .spelling(PitPuzzleConfig(
                    weight: entry.weight ?? 1,
                    numPaddingLetters: entry.numPaddingLetters
                        ?? PitPuzzleConfig.fallback.numPaddingLetters,
                    // `nil` → full shared catalog; YAML subsets via `words: [id, …]`.
                    wordIDs: entry.words?.map { $0.lowercased() },
                    // Filled by `resolveWords(from:)` after decode.
                    words: []
                ))
            case PitMinigameKind.bridge.rawValue:
                return .bridge(PitBridgeConfig(
                    weight: entry.weight ?? 1,
                    minWords: entry.minWords ?? PitBridgeConfig.defaultMinWords,
                    maxWords: entry.maxWords ?? PitBridgeConfig.defaultMaxWords,
                    words: entry.words ?? PitBridgeConfig.defaultWords
                ))
            default:
                throw WorldSeedError.decodeFailed("Unknown pit minigame type: '\(entry.type)'")
            }
        }
    }
}

private nonisolated struct PitConfigDTO: Decodable {
    var fx: SoundEffectTable?
    var minigames: [PitMinigameDTO]?
}

private nonisolated struct PitMinigameDTO: Decodable {
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
