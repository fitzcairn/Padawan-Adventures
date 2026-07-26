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

    static func fallbackEntry(word: String) -> GateWord {
        let w = word.lowercased()
        var progressive: [String: String] = [:]
        var prefix = ""
        for character in w {
            prefix.append(character)
            progressive[prefix] = "sfx_word_\(w)_\(prefix)"
        }
        return GateWord(word: w, spelling: "sfx_word_\(w)", progressive: progressive)
    }
}

/// Per-level gate letter-puzzle settings from `gate:` in level YAML.
/// Vocabulary lives in shared `Resources/Config/Vocab/words.yaml`; levels may optionally subset via `gate.words: [id, …]`.
nonisolated struct GatePuzzleConfig: Decodable, Equatable, Sendable {
    var timerSeconds: Double
    /// Optional override for shared `sound.yaml` `fx.win`; `nil` uses the common track.
    var winSound: String?
    /// Track basename played in the world when the gate strip opens after a win.
    var gateOpened: String
    /// Extra random letters beyond the chosen word (total sprites = word length + this).
    var numPaddingLetters: Int
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case winSound = "win_sound"
        case gateOpened = "gate_opened"
        case numPaddingLetters = "num_padding_letters"
        case words
    }

    nonisolated static let fallback = GatePuzzleConfig(
        timerSeconds: 30,
        gateOpened: "sfx_gate_opened",
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words
    )

    nonisolated init(
        timerSeconds: Double,
        winSound: String? = nil,
        gateOpened: String = "sfx_gate_opened",
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord]
    ) {
        self.timerSeconds = timerSeconds
        self.winSound = Self.normalizedOptionalTrack(winSound)
        self.gateOpened = gateOpened.trimmingCharacters(in: .whitespacesAndNewlines)
        self.numPaddingLetters = numPaddingLetters
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = Self.normalizedWords(words)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        winSound = Self.normalizedOptionalTrack(
            try container.decodeIfPresent(String.self, forKey: .winSound)
        )
        gateOpened = (
            try container.decodeIfPresent(String.self, forKey: .gateOpened)
                ?? Self.fallback.gateOpened
        ).trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard !gateOpened.isEmpty else {
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

    /// Trims YAML track basenames; blank values mean “use shared `sound.yaml` FX”.
    static func normalizedOptionalTrack(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Per-level pit spelling-hop settings from `pit:` in level YAML.
/// Vocabulary lives in shared `Resources/Config/Vocab/words.yaml`; levels may optionally subset via `pit.words: [id, …]`.
nonisolated struct PitPuzzleConfig: Decodable, Equatable, Sendable {
    var timerSeconds: Double
    /// Optional override for shared `sound.yaml` `fx.win`; `nil` uses the common track.
    var winSound: String?
    /// Optional override for shared `sound.yaml` `fx.lose`; `nil` uses the common track.
    var failSound: String?
    /// Extra random letters beyond the chosen word (total sprites = word length + this).
    var numPaddingLetters: Int
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case winSound = "win_sound"
        case failSound = "fail_sound"
        case numPaddingLetters = "num_padding_letters"
        case words
    }

    nonisolated static let fallback = PitPuzzleConfig(
        timerSeconds: 30,
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words.filter { ["cat", "dog", "star"].contains($0.word) }
    )

    nonisolated init(
        timerSeconds: Double,
        winSound: String? = nil,
        failSound: String? = nil,
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord]
    ) {
        self.timerSeconds = timerSeconds
        self.winSound = GatePuzzleConfig.normalizedOptionalTrack(winSound)
        self.failSound = GatePuzzleConfig.normalizedOptionalTrack(failSound)
        self.numPaddingLetters = numPaddingLetters
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = GatePuzzleConfig.normalizedWords(words)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        winSound = GatePuzzleConfig.normalizedOptionalTrack(
            try container.decodeIfPresent(String.self, forKey: .winSound)
        )
        failSound = GatePuzzleConfig.normalizedOptionalTrack(
            try container.decodeIfPresent(String.self, forKey: .failSound)
        )
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
    /// Max seconds between target-pronunciation plays before auto-replay.
    var letterSoundRepeatSeconds: Double
    /// Seconds after an incorrect tap before replaying the target pronunciation.
    var incorrectReplayDelaySeconds: Double
    /// Inclusive lower bound for letters chosen per round (clamped to the letter pool).
    var letterCountMin: Int
    /// Inclusive upper bound for letters chosen per round (clamped to the letter pool).
    var letterCountMax: Int
    /// Optional override for shared `sound.yaml` `fx.correct`; `nil` uses the common track.
    var correctSound: String?
    /// Track basename played in the world when the soft wall is destroyed after a win.
    var wallDestroyed: String
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var letterIDs: [String]?
    /// Resolved letters (sorted). Populated via `resolveLetters(from:)`.
    var letters: [DestructibleWallLetter]

    enum CodingKeys: String, CodingKey {
        case timerSeconds = "timer_seconds"
        case letterSoundRepeatSeconds = "letter_sound_repeat_seconds"
        case incorrectReplayDelaySeconds = "incorrect_replay_delay_seconds"
        case letterCountMin = "letter_count_min"
        case letterCountMax = "letter_count_max"
        case correctSound = "correct_sound"
        case wallDestroyed = "wall_destroyed"
        case letters
    }

    nonisolated static let fallback = DestructibleWallPuzzleConfig(
        timerSeconds: 30,
        letterSoundRepeatSeconds: 3,
        incorrectReplayDelaySeconds: 1,
        letterCountMin: 2,
        letterCountMax: 4,
        wallDestroyed: "sfx_wall_destroyed",
        letters: LetterCatalog.fallback.letters
    )

    nonisolated init(
        timerSeconds: Double,
        letterSoundRepeatSeconds: Double = 3,
        incorrectReplayDelaySeconds: Double = 1,
        letterCountMin: Int = 2,
        letterCountMax: Int = 4,
        correctSound: String? = nil,
        wallDestroyed: String = "sfx_wall_destroyed",
        letterIDs: [String]? = nil,
        letters: [DestructibleWallLetter]
    ) {
        self.timerSeconds = timerSeconds
        self.letterSoundRepeatSeconds = letterSoundRepeatSeconds
        self.incorrectReplayDelaySeconds = incorrectReplayDelaySeconds
        self.letterCountMin = letterCountMin
        self.letterCountMax = letterCountMax
        self.correctSound = GatePuzzleConfig.normalizedOptionalTrack(correctSound)
        self.wallDestroyed = wallDestroyed.trimmingCharacters(in: .whitespacesAndNewlines)
        self.letterIDs = letterIDs?.map { $0.lowercased() }
        self.letters = Self.normalizedLetters(letters)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timerSeconds = try container.decodeIfPresent(Double.self, forKey: .timerSeconds)
            ?? Self.fallback.timerSeconds
        letterSoundRepeatSeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .letterSoundRepeatSeconds
        ) ?? Self.fallback.letterSoundRepeatSeconds
        incorrectReplayDelaySeconds = try container.decodeIfPresent(
            Double.self,
            forKey: .incorrectReplayDelaySeconds
        ) ?? Self.fallback.incorrectReplayDelaySeconds
        letterCountMin = try container.decodeIfPresent(Int.self, forKey: .letterCountMin)
            ?? Self.fallback.letterCountMin
        letterCountMax = try container.decodeIfPresent(Int.self, forKey: .letterCountMax)
            ?? Self.fallback.letterCountMax
        correctSound = GatePuzzleConfig.normalizedOptionalTrack(
            try container.decodeIfPresent(String.self, forKey: .correctSound)
        )
        wallDestroyed = (
            try container.decodeIfPresent(String.self, forKey: .wallDestroyed)
                ?? Self.fallback.wallDestroyed
        ).trimmingCharacters(in: .whitespacesAndNewlines)

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
        guard letterSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidDestructibleWallLetterSoundRepeat(letterSoundRepeatSeconds)
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
        guard !wallDestroyed.isEmpty else {
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

/// Per-level map size and generation settings loaded from `base_level.yaml` / `Resources/Config/Levels/*.yaml`.
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
    /// Sprite id from `Screens/level_select.yaml` used for the level-select planet art.
    var levelSprite: String?
    /// SF Symbol name awarded to inventory on first level completion.
    var artifact: String
    /// Raw `music:` value; interpret with `MusicCue.parse`.
    var music: String?
    /// Per-minigame music overrides for this level.
    var gameMusic: GameMusicConfig
    /// Shared letter-name prompt replay interval (combat cues, wall puzzle, etc.).
    var letterSoundRepeatSeconds: Double
    var width: Int
    var height: Int
    var algorithm: String
    var roomCount: Int
    var corridorWidth: Int
    var room: WorldSeedConfig.RoomParams
    var enemies: WorldSeedConfig.EnemiesSpawnConfig?
    var pickups: WorldSeedConfig.PickupsSpawnConfig?
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
        case levelSprite = "level_sprite"
        case artifact
        case music
        case gameMusic = "game_music"
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
        levelSprite: nil,
        artifact: fallbackArtifact,
        music: "level_theme",
        gameMusic: .fallback,
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
        enemies: .init(types: ["horranth"], spawnChancePerRoom: 0.8),
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
        SoundEffectTable(events: [
            "wall_destroyed": destructibleWall.wallDestroyed,
            "gate_opened": gate.gateOpened,
        ])
    }

    nonisolated init(
        name: String,
        order: Int = 0,
        color: String = LevelConfig.fallbackColor,
        levelSprite: String? = nil,
        artifact: String = LevelConfig.fallbackArtifact,
        music: String? = nil,
        gameMusic: GameMusicConfig = .fallback,
        letterSoundRepeatSeconds: Double = 3,
        width: Int,
        height: Int,
        algorithm: String,
        roomCount: Int,
        corridorWidth: Int,
        room: WorldSeedConfig.RoomParams,
        enemies: WorldSeedConfig.EnemiesSpawnConfig? = nil,
        pickups: WorldSeedConfig.PickupsSpawnConfig? = nil,
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
        self.levelSprite = Self.normalizedOptionalID(levelSprite)
        self.artifact = artifact
        self.music = music
        self.gameMusic = gameMusic
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
        levelSprite = Self.normalizedOptionalID(
            try container.decodeIfPresent(String.self, forKey: .levelSprite)
        )
        artifact = try container.decodeIfPresent(String.self, forKey: .artifact) ?? Self.fallbackArtifact
        music = try container.decodeIfPresent(String.self, forKey: .music)
        gameMusic = try container.decodeIfPresent(GameMusicConfig.self, forKey: .gameMusic) ?? .fallback
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        roomCount = try container.decode(Int.self, forKey: .roomCount)
        corridorWidth = try container.decode(Int.self, forKey: .corridorWidth)
        room = try container.decode(WorldSeedConfig.RoomParams.self, forKey: .room)
        enemies = try container.decodeIfPresent(WorldSeedConfig.EnemiesSpawnConfig.self, forKey: .enemies)
        pickups = try container.decodeIfPresent(WorldSeedConfig.PickupsSpawnConfig.self, forKey: .pickups)
        pit = try container.decodeIfPresent(PitPuzzleConfig.self, forKey: .pit) ?? .fallback
        gate = try container.decodeIfPresent(GatePuzzleConfig.self, forKey: .gate) ?? .fallback
        let decodedWall = try container.decodeIfPresent(
            DestructibleWallPuzzleConfig.self,
            forKey: .destructibleWall
        ) ?? .fallback
        let topLevelRepeat = try container.decodeIfPresent(
            Double.self,
            forKey: .letterSoundRepeatSeconds
        )
        // Top-level shared cadence wins; otherwise keep wall-nested / fallback value.
        letterSoundRepeatSeconds = topLevelRepeat ?? decodedWall.letterSoundRepeatSeconds
        if let topLevelRepeat {
            destructibleWall = DestructibleWallPuzzleConfig(
                timerSeconds: decodedWall.timerSeconds,
                letterSoundRepeatSeconds: topLevelRepeat,
                incorrectReplayDelaySeconds: decodedWall.incorrectReplayDelaySeconds,
                letterCountMin: decodedWall.letterCountMin,
                letterCountMax: decodedWall.letterCountMax,
                correctSound: decodedWall.correctSound,
                wallDestroyed: decodedWall.wallDestroyed,
                letterIDs: decodedWall.letterIDs,
                letters: decodedWall.letters
            )
        } else {
            destructibleWall = decodedWall
        }
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
        guard !floorSprites.isEmpty else {
            throw WorldSeedError.emptyFloorSprites
        }
        guard floorAccentProb >= 0, floorAccentProb <= 1 else {
            throw WorldSeedError.invalidFloorAccentProb(floorAccentProb)
        }
        guard cornerSpecialProb >= 0, cornerSpecialProb <= 1 else {
            throw WorldSeedError.invalidCornerSpecialProb(cornerSpecialProb)
        }
        try pit.validate()
        try gate.validate()
        try destructibleWall.validate()
    }

    var musicCue: MusicCue {
        MusicCue.parse(music)
    }

    private static func normalizedOptionalID(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    var generation: WorldSeedConfig.GenerationParams {
        .init(
            algorithm: algorithm,
            roomCount: roomCount,
            corridorWidth: corridorWidth,
            room: room
        )
    }

    static func loadFromBundle(
        named name: String = "base_level",
        withExtension ext: String = "yaml",
        subdirectory: String? = nil,
        wordCatalog: WordCatalog? = nil,
        letterCatalog: LetterCatalog? = nil
    ) throws -> LevelConfig {
        let data = try resourceData(named: name, withExtension: ext, subdirectory: subdirectory)
        return try decode(
            from: data,
            parentDataNamed: { parentName in
                // Inherited bases live in Resources/Config/ (bundled at root).
                try resourceData(named: parentName, withExtension: ext, subdirectory: nil)
            },
            wordCatalog: wordCatalog,
            letterCatalog: letterCatalog
        )
    }

    /// Decodes YAML, resolving `inherits:` via `parentDataNamed` when provided (or required).
    /// Shared catalogs resolve gate words / wall letters from bundled YAML (or fallbacks).
    static func decode(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)? = nil,
        wordCatalog: WordCatalog? = nil,
        letterCatalog: LetterCatalog? = nil
    ) throws -> LevelConfig {
        do {
            let merged = try resolveInheritance(
                from: data,
                parentDataNamed: parentDataNamed,
                visited: []
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
                    throw WorldSeedError.missingResource
                }
                return Data(parentYAML.utf8)
            },
            wordCatalog: wordCatalog,
            letterCatalog: letterCatalog
        )
    }

    private static func loadWordCatalog() throws -> WordCatalog {
        do {
            return try WordCatalog.loadFromBundle()
        } catch WorldSeedError.missingResource {
            return .fallback
        }
    }

    private static func loadLetterCatalog() throws -> LetterCatalog {
        do {
            return try LetterCatalog.loadFromBundle()
        } catch WorldSeedError.missingResource {
            return .fallback
        }
    }

    nonisolated static func deepMerge(
        _ base: [String: Any],
        overwriting child: [String: Any]
    ) -> [String: Any] {
        var result = base
        for (key, value) in child {
            if let childDict = asStringKeyedDictionary(value),
               let baseDict = asStringKeyedDictionary(result[key] as Any?) {
                result[key] = deepMerge(baseDict, overwriting: childDict)
            } else {
                result[key] = normalizeYAMLValue(value)
            }
        }
        return result
    }

    private static func resolveInheritance(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)?,
        visited: Set<String>
    ) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw WorldSeedError.decodeFailed("level YAML is not valid UTF-8")
        }
        guard let loaded = try Yams.load(yaml: text),
              let dict = asStringKeyedDictionary(loaded) else {
            throw WorldSeedError.decodeFailed("level YAML did not decode to a dictionary")
        }

        var working = dict
        guard let inherits = working["inherits"] as? String else {
            return working
        }

        let parentName = (inherits as NSString).deletingPathExtension
        guard !visited.contains(parentName) else {
            throw WorldSeedError.decodeFailed("circular inherits involving '\(parentName)'")
        }
        guard let parentDataNamed else {
            throw WorldSeedError.missingResource
        }

        let parentData = try parentDataNamed(parentName)
        let resolvedParent = try resolveInheritance(
            from: parentData,
            parentDataNamed: parentDataNamed,
            visited: visited.union([parentName])
        )

        working.removeValue(forKey: "inherits")
        return deepMerge(resolvedParent, overwriting: working)
    }

    private static func resourceData(
        named name: String,
        withExtension ext: String,
        subdirectory: String?
    ) throws -> Data {
        // Prefer subdirectory when present; fall back to bundle root because Xcode may flatten
        // Resources/Config/Levels/*.yaml into the app bundle root.
        if let subdirectory,
           let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return try Data(contentsOf: url)
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw WorldSeedError.missingResource
        }
        return try Data(contentsOf: url)
    }

    private static func asStringKeyedDictionary(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalizeYAMLValue($0) }
        }
        if let dict = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, nested) in dict {
                guard let stringKey = key as? String else { continue }
                result[stringKey] = normalizeYAMLValue(nested)
            }
            return result
        }
        return nil
    }

    private static func normalizeYAMLValue(_ value: Any) -> Any {
        if let dict = asStringKeyedDictionary(value) {
            return dict
        }
        if let array = value as? [Any] {
            return array.map { normalizeYAMLValue($0) }
        }
        if let array = value as? NSArray {
            return array.map { normalizeYAMLValue($0) }
        }
        return value
    }
}

/// A playable level discovered from `Resources/Config/Levels/`.
nonisolated struct LevelDescriptor: Equatable, Sendable {
    let resourceName: String
    let displayName: String
    let order: Int
    /// Hex fill for the level-select planet sprite.
    let color: String
    /// Sprite id from `Screens/level_select.yaml` for the level-select planet art.
    let levelSprite: String?
}

nonisolated enum LevelCatalog {
    static let subdirectory = "Levels"

    /// Resource basenames that are shared config, not playable levels.
    private static let excludedResourceNames: Set<String> = [
        "base_level",
        "combat",
        "world",
        "sound",
        "player",
        "hud",
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
                    levelSprite: level.levelSprite
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
        if let nested = Bundle.main.urls(
            forResourcesWithExtension: ext,
            subdirectory: subdirectory
        ), !nested.isEmpty {
            return nested
        }

        // Flattened bundle layout: playable levels at root (exclude shared config YAML).
        let root = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        return root.filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            return !excludedResourceNames.contains(name)
                && !name.hasPrefix("sfx_")
                && name != "level_select"
                && name != "menu"
                && name != "settings"
        }
    }
}
