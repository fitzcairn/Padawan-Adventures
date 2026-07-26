import Foundation
import os
import Yams

private let levelCatalogLogger = Logger(subsystem: "PadawanAdventures", category: "LevelCatalog")

/// A shared / gate vocabulary entry: spelling track + progressive prefix tracks.
nonisolated struct GateWord: Equatable, Sendable {
    var word: String
    /// Full spelling cue, e.g. "s, t, a, r. Star".
    var spelling: String
    /// Prefix → track basename (`s`, `st`, `sta`, `star`, …).
    var progressive: [String: String]

    /// Convenience for the full-word spelling track (open / auto-repeat).
    var sound: String { spelling }

    func progressiveTrack(forPrefix prefix: String) -> String? {
        let key = prefix.lowercased()
        guard let track = progressive[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !track.isEmpty else {
            return nil
        }
        return track
    }

    static func fallbackEntry(word: String, fxPrefix: String = "sfx_word_") -> GateWord {
        let w = word.lowercased()
        let prefixBase = fxPrefix.isEmpty ? "sfx_word_" : fxPrefix
        var progressive: [String: String] = [:]
        var prefix = ""
        for character in w {
            prefix.append(character)
            progressive[prefix] = "\(prefixBase)\(w)_\(prefix)"
        }
        return GateWord(word: w, spelling: "\(prefixBase)\(w)", progressive: progressive)
    }
}

/// Per-level gate letter-puzzle settings from `gate:` in level YAML.
/// Vocabulary lives in shared `Resources/Config/Vocab/words.yaml`; levels may optionally subset via `gate.words: [id, …]`.
nonisolated struct GatePuzzleConfig: Decodable, Equatable, Sendable {
    var timerSeconds: Double
    /// Puzzle FX (`opened`, optional `win` override for shared `sound.yaml`).
    var fx: SoundEffectTable
    /// Extra random letters beyond the chosen word (total sprites = word length + this).
    var numPaddingLetters: Int
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case fx
        case numPaddingLetters = "num_padding_letters"
        case words
    }

    nonisolated static let fallback = GatePuzzleConfig(
        timerSeconds: 30,
        fx: SoundEffectTable(events: ["opened": "sfx_gate_opened"]),
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words
    )

    nonisolated init(
        timerSeconds: Double,
        fx: SoundEffectTable = SoundEffectTable(events: ["opened": "sfx_gate_opened"]),
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord]
    ) {
        self.timerSeconds = timerSeconds
        self.fx = fx
        self.numPaddingLetters = numPaddingLetters
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = Self.normalizedWords(words)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? Self.fallback.fx
        numPaddingLetters = try container.decodeIfPresent(Int.self, forKey: .numPaddingLetters)
            ?? Self.fallback.numPaddingLetters

        if container.contains(.words) {
            wordIDs = try container.decode([String].self, forKey: .words)
                .map { $0.lowercased() }
        } else {
            wordIDs = nil
        }
        // Filled by `resolveWords(from:)` after decode.
        words = []
    }

    mutating func resolveWords(from catalog: WordCatalog) throws {
        words = try catalog.resolve(ids: wordIDs)
    }

    func validate() throws {
        guard timerSeconds > 0 else {
            throw WorldSeedError.invalidGateTimer(timerSeconds)
        }
        guard numPaddingLetters >= 0 else {
            throw WorldSeedError.invalidGatePaddingLetters(numPaddingLetters)
        }
        guard fx.trackID(for: "opened") != nil else {
            throw WorldSeedError.invalidGateWords
        }
        guard !words.isEmpty else {
            throw WorldSeedError.invalidGateWords
        }
        let letterSet = CharacterSet.letters
        for entry in words {
            guard !entry.word.isEmpty,
                  entry.word.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorldSeedError.invalidGateWords
            }
            var prefix = ""
            for character in entry.word {
                prefix.append(character)
                guard let track = entry.progressive[prefix]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !track.isEmpty else {
                    throw WorldSeedError.invalidGateWords
                }
            }
        }
    }

    static func normalizedWords(_ words: [GateWord]) -> [GateWord] {
        words
            .map { entry in
                var progressive: [String: String] = [:]
                for (key, value) in entry.progressive {
                    progressive[key.lowercased()] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return GateWord(
                    word: entry.word.lowercased(),
                    spelling: entry.spelling.trimmingCharacters(in: .whitespacesAndNewlines),
                    progressive: progressive
                )
            }
            .sorted { $0.word < $1.word }
    }
}

/// Per-level pit spelling-hop settings from `pit:` in level YAML.
/// Vocabulary lives in shared `Resources/Config/Vocab/words.yaml`; levels may optionally subset via `pit.words: [id, …]`.
nonisolated struct PitPuzzleConfig: Decodable, Equatable, Sendable {
    var timerSeconds: Double
    /// Puzzle FX (`win` / `lose` override shared `sound.yaml` when present).
    var fx: SoundEffectTable
    /// Extra random letters beyond the chosen word (total sprites = word length + this).
    var numPaddingLetters: Int
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case fx
        case numPaddingLetters = "num_padding_letters"
        case words
    }

    nonisolated static let fallback = PitPuzzleConfig(
        timerSeconds: 30,
        fx: SoundEffectTable(events: [
            "win": "sfx_pit_yay",
            "lose": "sfx_pit_fall",
        ]),
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words.filter { ["cat", "dog", "star"].contains($0.word) }
    )

    nonisolated init(
        timerSeconds: Double,
        fx: SoundEffectTable = SoundEffectTable(events: [
            "win": "sfx_pit_yay",
            "lose": "sfx_pit_fall",
        ]),
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord]
    ) {
        self.timerSeconds = timerSeconds
        self.fx = fx
        self.numPaddingLetters = numPaddingLetters
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = GatePuzzleConfig.normalizedWords(words)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? Self.fallback.fx
        numPaddingLetters = try container.decodeIfPresent(Int.self, forKey: .numPaddingLetters)
            ?? Self.fallback.numPaddingLetters

        if container.contains(.words) {
            wordIDs = try container.decode([String].self, forKey: .words)
                .map { $0.lowercased() }
        } else {
            wordIDs = nil
        }
        // Filled by `resolveWords(from:)` after decode.
        words = []
    }

    mutating func resolveWords(from catalog: WordCatalog) throws {
        do {
            // `nil` wordIDs → full shared catalog (same as gate); YAML subsets via `words: [id, …]`.
            words = try catalog.resolve(ids: wordIDs)
        } catch WorldSeedError.invalidGateWords {
            throw WorldSeedError.invalidPitWords
        }
    }

    func validate() throws {
        guard timerSeconds > 0 else {
            throw WorldSeedError.invalidPitTimer(timerSeconds)
        }
        guard numPaddingLetters >= 0 else {
            throw WorldSeedError.invalidPitWords
        }
        guard !words.isEmpty else {
            throw WorldSeedError.invalidPitWords
        }
        let letterSet = CharacterSet.letters
        for entry in words {
            guard !entry.word.isEmpty,
                  entry.word.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorldSeedError.invalidPitWords
            }
            var prefix = ""
            for character in entry.word {
                prefix.append(character)
                guard let track = entry.progressive[prefix]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !track.isEmpty else {
                    throw WorldSeedError.invalidPitWords
                }
            }
        }
    }
}

/// A destructible-wall puzzle letter: glyph + pronunciation/name track basenames.
nonisolated struct DestructibleWallLetter: Equatable, Sendable {
    var letter: String
    var pronunciation: String
    var name: String
}

/// Per-level destructible-wall letter-matching settings from `destructible_wall:` in level YAML.
/// Letter FX lives in shared `Resources/Config/Vocab/letters.yaml`; levels may optionally subset via `letters: [id, …]`.
nonisolated struct DestructibleWallPuzzleConfig: Decodable, Equatable, Sendable {
    var timerSeconds: Double
    /// Seconds after an incorrect tap before replaying the target pronunciation.
    var incorrectReplayDelaySeconds: Double
    /// Inclusive lower bound for letters chosen per round (clamped to the letter pool).
    var letterCountMin: Int
    /// Inclusive upper bound for letters chosen per round (clamped to the letter pool).
    var letterCountMax: Int
    /// Puzzle FX (`destroyed`, optional `correct` override for shared `sound.yaml`).
    var fx: SoundEffectTable
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var letterIDs: [String]?
    /// Resolved letters (sorted). Populated via `resolveLetters(from:)`.
    var letters: [DestructibleWallLetter]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case incorrectReplayDelaySeconds = "incorrect_replay_delay_seconds"
        case letterCountMin = "letter_count_min"
        case letterCountMax = "letter_count_max"
        case fx
        case letters
    }

    nonisolated static let fallback = DestructibleWallPuzzleConfig(
        timerSeconds: 30,
        incorrectReplayDelaySeconds: 1,
        letterCountMin: 2,
        letterCountMax: 4,
        fx: SoundEffectTable(events: ["destroyed": "sfx_wall_destroyed"]),
        letters: LetterCatalog.fallback.letters
    )

    nonisolated init(
        timerSeconds: Double,
        incorrectReplayDelaySeconds: Double = 1,
        letterCountMin: Int = 2,
        letterCountMax: Int = 4,
        fx: SoundEffectTable = SoundEffectTable(events: ["destroyed": "sfx_wall_destroyed"]),
        letterIDs: [String]? = nil,
        letters: [DestructibleWallLetter]
    ) {
        self.timerSeconds = timerSeconds
        self.incorrectReplayDelaySeconds = incorrectReplayDelaySeconds
        self.letterCountMin = letterCountMin
        self.letterCountMax = letterCountMax
        self.fx = fx
        self.letterIDs = letterIDs?.map { $0.lowercased() }
        self.letters = Self.normalizedLetters(letters)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        incorrectReplayDelaySeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .incorrectReplayDelaySeconds
        ) ?? Self.fallback.incorrectReplayDelaySeconds
        letterCountMin = try container.decodeIfPresent(Int.self, forKey: .letterCountMin)
            ?? Self.fallback.letterCountMin
        letterCountMax = try container.decodeIfPresent(Int.self, forKey: .letterCountMax)
            ?? Self.fallback.letterCountMax
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? Self.fallback.fx

        if container.contains(.letters) {
            letterIDs = try container.decode([String].self, forKey: .letters)
                .map { $0.lowercased() }
        } else {
            letterIDs = nil
        }
        // Filled by `resolveLetters(from:)` after decode.
        letters = []
    }

    mutating func resolveLetters(from catalog: LetterCatalog) throws {
        letters = try catalog.resolve(ids: letterIDs)
    }

    func validate() throws {
        guard timerSeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallTimer(timerSeconds)
        }
        guard incorrectReplayDelaySeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallIncorrectReplayDelay(incorrectReplayDelaySeconds)
        }
        guard letterCountMin >= 1, letterCountMax >= letterCountMin else {
            throw WorldSeedError.invalidDestructibleWallLetterCountRange(
                min: letterCountMin,
                max: letterCountMax
            )
        }
        guard fx.trackID(for: "destroyed") != nil else {
            throw WorldSeedError.invalidDestructibleWallLetters
        }
        guard !letters.isEmpty else {
            throw WorldSeedError.invalidDestructibleWallLetters
        }
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for entry in letters {
            guard entry.letter.count == 1,
                  entry.letter.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.letter).inserted else {
                throw WorldSeedError.invalidDestructibleWallLetters
            }
        }
    }

    static func normalizedLetters(_ letters: [DestructibleWallLetter]) -> [DestructibleWallLetter] {
        letters
            .map {
                DestructibleWallLetter(
                    letter: $0.letter.lowercased(),
                    pronunciation: $0.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .sorted { $0.letter < $1.letter }
    }
}

/// Per-level minigame music track basenames (`Resources/Audio/Music/<name>.m4a`).
nonisolated struct GameMusicConfig: Codable, Equatable, Sendable {
    var combat: String?
    var pit: String?
    var destructibleWall: String?
    var gate: String?

    enum CodingKeys: String, CodingKey {
        case combat
        case pit
        case destructibleWall = "destructible_wall"
        case gate
    }

    nonisolated static let fallback = GameMusicConfig(
        combat: "combat_theme",
        pit: "pit_theme",
        destructibleWall: "destructible_wall_theme",
        gate: "gate_theme"
    )

    nonisolated init(
        combat: String? = nil,
        pit: String? = nil,
        destructibleWall: String? = nil,
        gate: String? = nil
    ) {
        self.combat = combat
        self.pit = pit
        self.destructibleWall = destructibleWall
        self.gate = gate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combat = try container.decodeIfPresent(String.self, forKey: .combat)
        pit = try container.decodeIfPresent(String.self, forKey: .pit)
        destructibleWall = try container.decodeIfPresent(String.self, forKey: .destructibleWall)
        gate = try container.decodeIfPresent(String.self, forKey: .gate)
    }

    var combatCue: MusicCue { MusicCue.parse(combat) }
    var pitCue: MusicCue { MusicCue.parse(pit) }
    var destructibleWallCue: MusicCue { MusicCue.parse(destructibleWall) }
    var gateCue: MusicCue { MusicCue.parse(gate) }
}

/// Per-level minigame still backgrounds (`Resources/Backgrounds/<name>.png`).
nonisolated struct GameBackgroundConfig: Codable, Equatable, Sendable {
    var combat: String?
    var pit: String?
    var destructibleWall: String?
    var gate: String?

    enum CodingKeys: String, CodingKey {
        case combat
        case pit
        case destructibleWall = "destructible_wall"
        case gate
    }

    nonisolated static let fallback = GameBackgroundConfig(
        combat: nil,
        pit: nil,
        destructibleWall: nil,
        gate: nil
    )

    nonisolated init(
        combat: String? = nil,
        pit: String? = nil,
        destructibleWall: String? = nil,
        gate: String? = nil
    ) {
        self.combat = Self.normalized(combat)
        self.pit = Self.normalized(pit)
        self.destructibleWall = Self.normalized(destructibleWall)
        self.gate = Self.normalized(gate)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combat = Self.normalized(try container.decodeIfPresent(String.self, forKey: .combat))
        pit = Self.normalized(try container.decodeIfPresent(String.self, forKey: .pit))
        destructibleWall = Self.normalized(
            try container.decodeIfPresent(String.self, forKey: .destructibleWall)
        )
        gate = Self.normalized(try container.decodeIfPresent(String.self, forKey: .gate))
    }

    /// Unique non-empty background basenames from this minigame block.
    var backgroundNames: [String] {
        [combat, pit, destructibleWall, gate].compactMap { $0 }
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Per-level map size and generation settings loaded from `Levels/_defaults.yaml` / `Resources/Config/Levels/*.yaml`.
nonisolated struct LevelConfig: Decodable, Equatable, Sendable {
    /// Default SF Symbol used when a level omits `artifact:`.
    static let fallbackArtifact = "star.fill"
    /// Default map-sprite fill when a level omits `color:`.
    static let fallbackColor = "#888888"

    var name: String
    /// Sort key for level-select progression (lower first).
    var order: Int
    /// Hex fill for the level-select planet sprite (`#RRGGBB`).
    var color: String
    /// Level-select planet art (`Resources/Sprites/UI/Levels/...`).
    var sprite: SpriteConfig?
    /// SF Symbol name awarded to inventory on first level completion.
    var artifact: String
    /// Raw `music:` value; interpret with `MusicCue.parse`.
    var music: String?
    /// Per-minigame music overrides for this level.
    var gameMusic: GameMusicConfig
    /// Still image basename under `Resources/Backgrounds/` for the main game scene.
    var background: String?
    /// Per-minigame still backgrounds for this level.
    var gameBackground: GameBackgroundConfig
    /// Shared letter-name prompt replay interval (combat cues, wall puzzle, etc.).
    var letterSoundRepeatSeconds: Double
    var width: Int
    var height: Int
    var algorithm: String
    var roomCount: Int
    var corridorWidth: Int
    var room: RoomParams
    var enemies: EnemiesSpawnConfig?
    var pickups: PickupsSpawnConfig?
    var pit: PitPuzzleConfig
    var gate: GatePuzzleConfig
    var destructibleWall: DestructibleWallPuzzleConfig
    /// Base terrain ids from `terrain.yaml` used when painting floor tiles for this level.
    var floorSprites: [String]
    /// Probability that a non-corner floor gets an accent overlay (0...1).
    var floorAccentProb: Double
    /// Probability that a corner floor (exactly 2 orthogonal floor neighbors) becomes a special (0...1).
    var cornerSpecialProb: Double

    enum CodingKeys: String, CodingKey {
        case name
        case order
        case color
        case sprite
        case artifact
        case music
        case gameMusic = "game_music"
        case background
        case gameBackground = "game_background"
        case letterSoundRepeatSeconds = "letter_sound_repeat_seconds"
        case width
        case height
        case algorithm
        case roomCount = "room_count"
        case corridorWidth = "corridor_width"
        case room
        case enemies
        case pickups
        case pit
        case gate
        case destructibleWall = "destructible_wall"
        case floorSprites = "floor_sprites"
        case floorAccentProb = "floor_accent_prob"
        case cornerSpecialProb = "corner_special_prob"
    }

    /// Default mixed base palette when a level omits `floor_sprites:`.
    static let fallbackFloorSprites = [
        "grass",
        "grass-lush",
        "dirt-arid",
        "dirt-dry",
        "sand",
        "plank",
        "water",
    ]

    static let fallbackFloorAccentProb = 0.15
    static let fallbackCornerSpecialProb = 0.15

    nonisolated static let fallback = LevelConfig(
        name: "Level 1",
        order: 0,
        color: fallbackColor,
        sprite: nil,
        artifact: fallbackArtifact,
        music: "level_theme",
        gameMusic: .fallback,
        background: nil,
        gameBackground: .fallback,
        letterSoundRepeatSeconds: 3,
        width: 100,
        height: 100,
        algorithm: "rooms_doors",
        roomCount: 100,
        corridorWidth: 2,
        room: .init(
            minRoomSize: 4,
            maxRoomSize: 12,
            pitChance: 0.2,
            pitMeanSize: 2,
            pitMaxSize: 5,
            wallDestructibleChance: 0.8,
            gateChance: 0.5
        ),
        enemies: .init(types: ["spider"], spawnChancePerRoom: 0.8),
        pickups: .init(
            health: .init(spawnChancePerRoom: 0.8),
            energy: .init(spawnChancePerRoom: 0.8)
        ),
        pit: .fallback,
        gate: .fallback,
        destructibleWall: .fallback,
        floorSprites: fallbackFloorSprites,
        floorAccentProb: fallbackFloorAccentProb,
        cornerSpecialProb: fallbackCornerSpecialProb
    )

    /// World interaction FX synthesized from puzzle configs (`wall_destroyed`, `gate_opened`).
    var worldFx: SoundEffectTable {
        var events: [String: String] = [:]
        if let destroyed = destructibleWall.fx.trackID(for: "destroyed") {
            events["wall_destroyed"] = destroyed
        }
        if let opened = gate.fx.trackID(for: "opened") {
            events["gate_opened"] = opened
        }
        return SoundEffectTable(events: events)
    }

    nonisolated init(
        name: String,
        order: Int = 0,
        color: String = LevelConfig.fallbackColor,
        sprite: SpriteConfig? = nil,
        artifact: String = LevelConfig.fallbackArtifact,
        music: String? = nil,
        gameMusic: GameMusicConfig = .fallback,
        background: String? = nil,
        gameBackground: GameBackgroundConfig = .fallback,
        letterSoundRepeatSeconds: Double = 3,
        width: Int,
        height: Int,
        algorithm: String,
        roomCount: Int,
        corridorWidth: Int,
        room: RoomParams,
        enemies: EnemiesSpawnConfig? = nil,
        pickups: PickupsSpawnConfig? = nil,
        pit: PitPuzzleConfig = .fallback,
        gate: GatePuzzleConfig = .fallback,
        destructibleWall: DestructibleWallPuzzleConfig = .fallback,
        floorSprites: [String] = LevelConfig.fallbackFloorSprites,
        floorAccentProb: Double = LevelConfig.fallbackFloorAccentProb,
        cornerSpecialProb: Double = LevelConfig.fallbackCornerSpecialProb
    ) {
        self.name = name
        self.order = order
        self.color = color
        self.sprite = sprite
        self.artifact = artifact
        self.music = music
        self.gameMusic = gameMusic
        self.background = Self.normalizedOptionalID(background)
        self.gameBackground = gameBackground
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.width = width
        self.height = height
        self.algorithm = algorithm
        self.roomCount = roomCount
        self.corridorWidth = corridorWidth
        self.room = room
        self.enemies = enemies
        self.pickups = pickups
        self.pit = pit
        self.gate = gate
        self.destructibleWall = destructibleWall
        self.floorSprites = floorSprites
        self.floorAccentProb = floorAccentProb
        self.cornerSpecialProb = cornerSpecialProb
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        color = (
            try container.decodeIfPresent(String.self, forKey: .color) ?? Self.fallbackColor
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        sprite = try container.decodeIfPresent(SpriteConfig.self, forKey: .sprite)
        artifact = try container.decodeIfPresent(String.self, forKey: .artifact) ?? Self.fallbackArtifact
        music = try container.decodeIfPresent(String.self, forKey: .music)
        gameMusic = try container.decodeIfPresent(GameMusicConfig.self, forKey: .gameMusic) ?? .fallback
        background = Self.normalizedOptionalID(
            try container.decodeIfPresent(String.self, forKey: .background)
        )
        gameBackground = try container.decodeIfPresent(
            GameBackgroundConfig.self,
            forKey: .gameBackground
        ) ?? .fallback
        letterSoundRepeatSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .letterSoundRepeatSeconds
        ) ?? Self.fallback.letterSoundRepeatSeconds
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        roomCount = try container.decode(Int.self, forKey: .roomCount)
        corridorWidth = try container.decode(Int.self, forKey: .corridorWidth)
        room = try container.decode(RoomParams.self, forKey: .room)
        enemies = try container.decodeIfPresent(EnemiesSpawnConfig.self, forKey: .enemies)
        pickups = try container.decodeIfPresent(PickupsSpawnConfig.self, forKey: .pickups)
        pit = try container.decodeIfPresent(PitPuzzleConfig.self, forKey: .pit) ?? .fallback
        gate = try container.decodeIfPresent(GatePuzzleConfig.self, forKey: .gate) ?? .fallback
        destructibleWall = try container.decodeIfPresent(
            DestructibleWallPuzzleConfig.self,
            forKey: .destructibleWall
        ) ?? .fallback
        floorSprites = try container.decodeIfPresent([String].self, forKey: .floorSprites)
            ?? Self.fallbackFloorSprites
        floorAccentProb = try container.decodeIfPresent(Double.self, forKey: .floorAccentProb)
            ?? Self.fallbackFloorAccentProb
        cornerSpecialProb = try container.decodeIfPresent(Double.self, forKey: .cornerSpecialProb)
            ?? Self.fallbackCornerSpecialProb
    }

    func validate() throws {
        guard letterSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallLetterSoundRepeat(letterSoundRepeatSeconds)
        }
        guard width > 4, height > 4 else {
            throw WorldSeedError.worldTooSmall
        }
        guard corridorWidth >= 2 else {
            throw WorldSeedError.corridorTooNarrow(corridorWidth)
        }
        guard room.minRoomSize >= 2 else {
            throw WorldSeedError.roomTooNarrow(room.minRoomSize)
        }
        guard room.maxRoomSize >= room.minRoomSize else {
            throw WorldSeedError.invalidRoomSizeRange
        }
        guard room.pitChance >= 0, room.pitChance <= 1 else {
            throw WorldSeedError.invalidRoomPitChance(room.pitChance)
        }
        guard room.pitMaxSize >= 1 else {
            throw WorldSeedError.invalidRoomPitSize(mean: room.pitMeanSize, max: room.pitMaxSize)
        }
        guard room.pitMeanSize >= 1, room.pitMeanSize <= Double(room.pitMaxSize) else {
            throw WorldSeedError.invalidRoomPitSize(mean: room.pitMeanSize, max: room.pitMaxSize)
        }
        guard room.wallDestructibleChance >= 0, room.wallDestructibleChance <= 1 else {
            throw WorldSeedError.invalidRoomWallDestructibleChance(room.wallDestructibleChance)
        }
        guard room.gateChance >= 0, room.gateChance <= 1 else {
            throw WorldSeedError.invalidRoomGateChance(room.gateChance)
        }
        guard !floorSprites.isEmpty else {
            throw WorldSeedError.emptyFloorSprites
        }
        guard floorAccentProb >= 0, floorAccentProb <= 1 else {
            throw WorldSeedError.invalidFloorAccentProb(floorAccentProb)
        }
        guard cornerSpecialProb >= 0, cornerSpecialProb <= 1 else {
            throw WorldSeedError.invalidCornerSpecialProb(cornerSpecialProb)
        }
        if let enemies {
            guard !enemies.types.isEmpty, enemies.types.allSatisfy({ !$0.isEmpty }) else {
                throw WorldSeedError.invalidEnemyType
            }
            guard enemies.spawnChancePerRoom >= 0, enemies.spawnChancePerRoom <= 1 else {
                throw WorldSeedError.invalidEnemySpawnChance(enemies.spawnChancePerRoom)
            }
        }
        if let pickups {
            try Self.validatePickupChance(pickups.health?.spawnChancePerRoom, kind: .health)
            try Self.validatePickupChance(pickups.energy?.spawnChancePerRoom, kind: .energy)
        }
        try pit.validate()
        try gate.validate()
        try destructibleWall.validate()
    }

    private static func validatePickupChance(_ chance: Double?, kind: PickupKind) throws {
        guard let chance else { return }
        guard chance >= 0, chance <= 1 else {
            throw WorldSeedError.invalidPickupSpawnChance(kind: kind, chance: chance)
        }
    }

    var musicCue: MusicCue {
        MusicCue.parse(music)
    }

    /// Unique engine background basenames for this level (main scene + minigames).
    var engineBackgroundNames: [String] {
        var names: [String] = []
        if let background {
            names.append(background)
        }
        names.append(contentsOf: gameBackground.backgroundNames)
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private static func normalizedOptionalID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    var generation: GenerationParams {
        .init(
            algorithm: algorithm,
            roomCount: roomCount,
            corridorWidth: corridorWidth,
            room: room
        )
    }

    nonisolated struct GenerationParams: Codable, Equatable, Sendable {
        var algorithm: String
        var roomCount: Int
        var corridorWidth: Int
        var room: RoomParams

        enum CodingKeys: String, CodingKey {
            case algorithm
            case roomCount = "room_count"
            case corridorWidth = "corridor_width"
            case room
        }

        nonisolated init(
            algorithm: String,
            roomCount: Int,
            corridorWidth: Int,
            room: RoomParams
        ) {
            self.algorithm = algorithm
            self.roomCount = roomCount
            self.corridorWidth = corridorWidth
            self.room = room
        }

        /// Convenience for tests / fallbacks.
        nonisolated init(
            algorithm: String,
            roomCount: Int,
            corridorWidth: Int,
            minRoomSize: Int = 4,
            maxRoomSize: Int = 12,
            pitChance: Double,
            pitMeanSize: Double = 2,
            pitMaxSize: Int = 5,
            wallDestructibleChance: Double,
            gateChance: Double = 0.5
        ) {
            self.init(
                algorithm: algorithm,
                roomCount: roomCount,
                corridorWidth: corridorWidth,
                room: RoomParams(
                    minRoomSize: minRoomSize,
                    maxRoomSize: maxRoomSize,
                    pitChance: pitChance,
                    pitMeanSize: pitMeanSize,
                    pitMaxSize: pitMaxSize,
                    wallDestructibleChance: wallDestructibleChance,
                    gateChance: gateChance
                )
            )
        }
    }

    /// Per-room generation knobs (sizes, pit/soft-wall chances, etc.).
    nonisolated struct RoomParams: Codable, Equatable, Sendable {
        var minRoomSize: Int
        var maxRoomSize: Int
        /// Probability that a room contains a pit (at most one pit area per room).
        var pitChance: Double
        /// Expected pit area size in tiles (clamped to `1...pitMaxSize`).
        var pitMeanSize: Double
        /// Maximum pit area size in tiles.
        var pitMaxSize: Int
        var wallDestructibleChance: Double
        /// Probability that a door opening becomes a gate strip.
        var gateChance: Double

        enum CodingKeys: String, CodingKey {
            case minRoomSize = "min_room_size"
            case maxRoomSize = "max_room_size"
            case pitChance = "pit_chance"
            case pitMeanSize = "pit_mean_size"
            case pitMaxSize = "pit_max_size"
            case wallDestructibleChance = "wall_destructible_chance"
            case gateChance = "gate_chance"
        }

        nonisolated init(
            minRoomSize: Int = 4,
            maxRoomSize: Int = 12,
            pitChance: Double,
            pitMeanSize: Double = 2,
            pitMaxSize: Int = 5,
            wallDestructibleChance: Double,
            gateChance: Double = 0.5
        ) {
            self.minRoomSize = minRoomSize
            self.maxRoomSize = maxRoomSize
            self.pitChance = pitChance
            self.pitMeanSize = pitMeanSize
            self.pitMaxSize = pitMaxSize
            self.wallDestructibleChance = wallDestructibleChance
            self.gateChance = gateChance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            minRoomSize = try container.decodeIfPresent(Int.self, forKey: .minRoomSize) ?? 4
            maxRoomSize = try container.decodeIfPresent(Int.self, forKey: .maxRoomSize) ?? 12
            pitChance = try container.decode(Double.self, forKey: .pitChance)
            pitMeanSize = try container.decodeIfPresent(Double.self, forKey: .pitMeanSize) ?? 2
            pitMaxSize = try container.decodeIfPresent(Int.self, forKey: .pitMaxSize) ?? 5
            wallDestructibleChance = try container.decode(Double.self, forKey: .wallDestructibleChance)
            gateChance = try container.decodeIfPresent(Double.self, forKey: .gateChance) ?? 0.5
        }
    }

    nonisolated struct EnemiesSpawnConfig: Codable, Equatable, Sendable {
        /// Enemy type ids from `combat.yaml` (one or more; spawn picks uniformly).
        var types: [String]
        var spawnChancePerRoom: Double

        /// First configured type id (legacy single-type callers / tests).
        var type: String { types.first ?? "" }

        enum CodingKeys: String, CodingKey {
            case type
            case types
            case spawnChancePerRoom = "spawn_chance_per_room"
        }

        nonisolated init(type: String, spawnChancePerRoom: Double) {
            self.types = [type]
            self.spawnChancePerRoom = spawnChancePerRoom
        }

        nonisolated init(types: [String], spawnChancePerRoom: Double) {
            self.types = types
            self.spawnChancePerRoom = spawnChancePerRoom
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            spawnChancePerRoom = try container.decode(Double.self, forKey: .spawnChancePerRoom)
            if let list = try container.decodeIfPresent([String].self, forKey: .types), !list.isEmpty {
                types = list
            } else if let single = try container.decodeIfPresent(String.self, forKey: .type) {
                types = [single]
            } else {
                types = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(types, forKey: .types)
            try container.encode(spawnChancePerRoom, forKey: .spawnChancePerRoom)
        }
    }

    struct PickupChanceConfig: Codable, Equatable, Sendable {
        var spawnChancePerRoom: Double

        enum CodingKeys: String, CodingKey {
            case spawnChancePerRoom = "spawn_chance_per_room"
        }

        init(spawnChancePerRoom: Double) {
            self.spawnChancePerRoom = spawnChancePerRoom
        }
    }

    struct PickupsSpawnConfig: Codable, Equatable, Sendable {
        var health: PickupChanceConfig?
        var energy: PickupChanceConfig?

        init(
            health: PickupChanceConfig? = nil,
            energy: PickupChanceConfig? = nil
        ) {
            self.health = health
            self.energy = energy
        }
    }

    static func loadFromBundle(
        named name: String = "_defaults",
        withExtension ext: String = "yaml",
        subdirectory: String? = LevelCatalog.subdirectory,
        wordCatalog: WordCatalog? = nil,
        letterCatalog: LetterCatalog? = nil
    ) throws -> LevelConfig {
        let path: ConfigPath
        if name == ConfigPath.levelDefaults.basename {
            path = .levelDefaults
        } else if subdirectory == LevelCatalog.subdirectory {
            path = .level(name)
        } else {
            path = ConfigPath(basename: name, subdirectory: subdirectory)
        }
        let data = try ConfigStore.data(at: path)
        return try decode(
            from: data,
            parentDataNamed: { parentName in
                // Inherited bases live alongside level files in Levels/.
                try ConfigStore.data(at: ConfigPath.level(parentName))
            },
            fileLabel: path.description,
            wordCatalog: wordCatalog,
            letterCatalog: letterCatalog
        )
    }

    /// Decodes YAML, resolving `inherits:` via `parentDataNamed` when provided (or required).
    /// Shared catalogs resolve gate words / wall letters from bundled YAML (or fallbacks).
    static func decode(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)? = nil,
        fileLabel: String = "level",
        wordCatalog: WordCatalog? = nil,
        letterCatalog: LetterCatalog? = nil
    ) throws -> LevelConfig {
        do {
            let merged = try ConfigStore.rawTree(
                from: data,
                parentDataNamed: parentDataNamed,
                fileLabel: fileLabel
            )
            let yaml = try Yams.dump(object: merged)
            var level = try YAMLDecoder().decode(LevelConfig.self, from: yaml)
            let words = try wordCatalog ?? Self.loadWordCatalog()
            let letters = try letterCatalog ?? Self.loadLetterCatalog()
            try level.pit.resolveWords(from: words)
            try level.gate.resolveWords(from: words)
            try level.destructibleWall.resolveLetters(from: letters)
            try level.validate()
            return level
        } catch let error as ConfigError {
            throw error
        } catch let error as WorldSeedError {
            throw error
        } catch {
            throw WorldSeedError.decodeFailed(String(describing: error))
        }
    }

    static func decode(
        from yaml: String,
        wordCatalog: WordCatalog? = nil,
        letterCatalog: LetterCatalog? = nil
    ) throws -> LevelConfig {
        try decode(
            from: Data(yaml.utf8),
            wordCatalog: wordCatalog,
            letterCatalog: letterCatalog
        )
    }

    /// Test/helper entry that resolves `inherits:` against in-memory parent YAML documents.
    static func decode(
        from yaml: String,
        parents: [String: String],
        wordCatalog: WordCatalog? = nil,
        letterCatalog: LetterCatalog? = nil
    ) throws -> LevelConfig {
        try decode(
            from: Data(yaml.utf8),
            parentDataNamed: { name in
                guard let parentYAML = parents[name] else {
                    throw ConfigError.unknownParent(file: "level", parent: name)
                }
                return Data(parentYAML.utf8)
            },
            fileLabel: "level",
            wordCatalog: wordCatalog,
            letterCatalog: letterCatalog
        )
    }

    private static func loadWordCatalog() throws -> WordCatalog {
        do {
            return try WordCatalog.loadFromBundle()
        } catch ConfigError.missingResource {
            return .fallback
        }
    }

    private static func loadLetterCatalog() throws -> LetterCatalog {
        do {
            return try LetterCatalog.loadFromBundle()
        } catch ConfigError.missingResource {
            return .fallback
        }
    }
}

/// A playable level discovered from `Resources/Config/Levels/`.
nonisolated struct LevelDescriptor: Equatable, Sendable {
    let resourceName: String
    let displayName: String
    let order: Int
    /// Hex fill for the level-select planet sprite.
    let color: String
    /// Level-select planet art from the level YAML `sprite:` block.
    let sprite: SpriteConfig?
}

nonisolated enum LevelCatalog {
    static let subdirectory = "Levels"

    /// Resource basenames that are shared config, not playable levels.
    private static let excludedResourceNames: Set<String> = [
        "_defaults",
    ]

    static func loadFromBundle(
        withExtension ext: String = "yaml"
    ) -> [LevelDescriptor] {
        let urls = levelResourceURLs(withExtension: ext)

        return urls.compactMap { url -> LevelDescriptor? in
            let resourceName = url.deletingPathExtension().lastPathComponent
            guard !excludedResourceNames.contains(resourceName) else { return nil }
            do {
                let level = try LevelConfig.loadFromBundle(
                    named: resourceName,
                    withExtension: ext,
                    subdirectory: subdirectory
                )
                return LevelDescriptor(
                    resourceName: resourceName,
                    displayName: level.name,
                    order: level.order,
                    color: level.color,
                    sprite: level.sprite
                )
            } catch {
                levelCatalogLogger.error(
                    "Failed to load level '\(resourceName, privacy: .public)': \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
        .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.resourceName < $1.resourceName
        }
    }

    private static func levelResourceURLs(withExtension ext: String) -> [URL] {
        Bundle.main.urls(
            forResourcesWithExtension: ext,
            subdirectory: subdirectory
        ) ?? []
    }
}
