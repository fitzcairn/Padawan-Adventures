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

/// Per-entry gate spelling-puzzle config (was `GatePuzzleConfig`).
/// Vocabulary lives in shared `Resources/Config/Vocab/words.yaml`; levels may optionally subset via `words: [id, …]`.
nonisolated struct GateSpellingConfig: Equatable, Sendable {
    var timerSeconds: Double
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
        timerSeconds: 30,
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words,
        music: "gate"
    )

    nonisolated init(
        timerSeconds: Double,
        fx: SoundEffectTable = SoundEffectTable(),
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord],
        music: String? = nil
    ) {
        self.timerSeconds = timerSeconds
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
        guard timerSeconds > 0 else {
            throw WorldSeedError.invalidGateTimer(timerSeconds)
        }
        guard numPaddingLetters >= 0 else {
            throw WorldSeedError.invalidGatePaddingLetters(numPaddingLetters)
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
            "lose": "pit-falling",
            "jump": "pit-jump",
        ]),
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words.filter { ["cat", "dog", "star"].contains($0.word) }
    )

    nonisolated init(
        timerSeconds: Double,
        fx: SoundEffectTable = SoundEffectTable(events: [
            "lose": "pit-falling",
            "jump": "pit-jump",
        ]),
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord]
    ) {
        self.timerSeconds = timerSeconds
        self.fx = fx
        self.numPaddingLetters = numPaddingLetters
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = GateSpellingConfig.normalizedWords(words)
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

/// A gate letter-match puzzle letter: glyph + pronunciation/name track basenames.
nonisolated struct GateLetter: Equatable, Sendable {
    var letter: String
    var pronunciation: String
    var name: String
}

/// Per-entry gate letter-matching config.
/// Letter FX lives in shared `Resources/Config/Catalogs/letters.yaml`; levels may optionally subset via `letters: [id, …]`.
nonisolated struct GateLetterMatchConfig: Equatable, Sendable {
    var timerSeconds: Double
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
        timerSeconds: 30,
        incorrectReplayDelaySeconds: 1,
        letterCountMin: 4,
        letterCountMax: 8,
        letters: LetterCatalog.fallback.letters,
        music: "gate"
    )

    nonisolated init(
        timerSeconds: Double,
        incorrectReplayDelaySeconds: Double = 1,
        letterCountMin: Int = 4,
        letterCountMax: Int = 8,
        fx: SoundEffectTable = SoundEffectTable(),
        letterIDs: [String]? = nil,
        letters: [GateLetter],
        music: String? = nil
    ) {
        self.timerSeconds = timerSeconds
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
        guard timerSeconds > 0 else {
            throw WorldSeedError.invalidGateLetterMatchTimer(timerSeconds)
        }
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
        let letterSet = CharacterSet.letters
        var seen = Set<String>()
        for entry in letters {
            guard entry.letter.count == 1,
                  entry.letter.unicodeScalars.allSatisfy({ letterSet.contains($0) }),
                  !entry.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(entry.letter).inserted else {
                throw WorldSeedError.invalidGateLetterMatchLetters
            }
        }
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

/// Discriminator for which gate puzzle a tile/strip runs. YAML raw values match minigame `type:`.
nonisolated enum GateMinigameKind: String, Codable, Equatable, Sendable, CaseIterable {
    case spelling
    case letterMatch = "letter_match"
}

/// Discriminated union over the gate minigame entries in level YAML.
nonisolated enum GateMinigameConfig: Equatable, Sendable {
    case spelling(GateSpellingConfig)
    case letterMatch(GateLetterMatchConfig)

    var kind: GateMinigameKind {
        switch self {
        case .spelling: .spelling
        case .letterMatch: .letterMatch
        }
    }

    var music: String? {
        switch self {
        case .spelling(let c): c.music
        case .letterMatch(let c): c.music
        }
    }
}

/// Resolved gate host config from level YAML `gate:`.
nonisolated struct GateConfig: Equatable, Sendable {
    /// Must include `"opened"` — the world-level gate-open SFX.
    var fx: SoundEffectTable
    var minigames: [GateMinigameConfig]

    nonisolated static let fallback = GateConfig(
        fx: SoundEffectTable(events: ["opened": "gate-open"]),
        minigames: [
            .spelling(.fallback),
            .letterMatch(.fallback),
        ]
    )

    nonisolated init(fx: SoundEffectTable, minigames: [GateMinigameConfig]) {
        self.fx = fx
        self.minigames = minigames
    }

    func validate() throws {
        guard fx.trackID(for: "opened") != nil else {
            throw WorldSeedError.invalidGateWords
        }
        guard !minigames.isEmpty else {
            throw WorldSeedError.decodeFailed("gate.minigames must not be empty")
        }
        for minigame in minigames {
            switch minigame {
            case .spelling(let c): try c.validate()
            case .letterMatch(let c): try c.validate()
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
    func pickMinigameKind(using rng: inout some RandomNumberGenerator) -> GateMinigameKind {
        let kinds = distinctMinigameKinds
        precondition(!kinds.isEmpty)
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
            }
        }
    }
}

/// Per-level minigame music track basenames (`Resources/Audio/Music/<name>.mp3`).
nonisolated struct GameMusicConfig: Codable, Equatable, Sendable {
    var combat: String?
    var pit: String?
    var gate: String?

    enum CodingKeys: String, CodingKey {
        case combat
        case pit
        case gate
    }

    nonisolated static let fallback = GameMusicConfig(
        combat: "combat",
        pit: "pit",
        gate: "gate"
    )

    nonisolated init(
        combat: String? = nil,
        pit: String? = nil,
        gate: String? = nil
    ) {
        self.combat = combat
        self.pit = pit
        self.gate = gate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        combat = try container.decodeIfPresent(String.self, forKey: .combat)
        pit = try container.decodeIfPresent(String.self, forKey: .pit)
        gate = try container.decodeIfPresent(String.self, forKey: .gate)
    }

    var combatCue: MusicCue { MusicCue.parse(combat) }
    var pitCue: MusicCue { MusicCue.parse(pit) }
    var gateCue: MusicCue { MusicCue.parse(gate) }
}

/// Per-level map size and generation settings loaded from `Levels/_defaults.yaml` / `Levels/<id>/level.yaml`.
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
    /// Level-select planet art (`Levels/<id>/<id>-planet-*`).
    var sprite: SpriteConfig?
    /// SF Symbol name awarded to inventory on first level completion.
    var artifact: String
    /// Item id from `items.yaml` for this level's in-world treasure pickup.
    var treasure: String?
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
    var room: RoomParams
    var enemies: EnemiesSpawnConfig?
    var pickups: PickupsSpawnConfig?
    var pit: PitPuzzleConfig
    var gate: GateConfig
    /// Per-level baked floor tile set (`Levels/{set}/{set}-floor-*`).
    var floor: Floor
    /// Per-level baked letter glyph set (`Levels/{set}/{set}-letters-*`).
    var letters: Letters

    /// Floor tile set reference and decor sprinkle probability.
    nonisolated struct Floor: Codable, Equatable, Sendable {
        var set: String
        var decorProb: Double

        enum CodingKeys: String, CodingKey {
            case set
            case decorProb = "decor_prob"
        }

        nonisolated init(set: String = LevelConfig.offlineFallbackSet, decorProb: Double = 0.06) {
            self.set = set
            self.decorProb = decorProb
        }

        /// An absent `set:` decodes empty and is filled in from the level's folder
        /// name by `LevelConfig.decode`. Defaulting to a real set here would silently
        /// give a level another level's art.
        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            set = try c.decodeIfPresent(String.self, forKey: .set) ?? ""
            decorProb = try c.decodeIfPresent(Double.self, forKey: .decorProb) ?? 0.06
        }
    }

    /// Letter glyph set reference for combat / puzzle letter sprites.
    nonisolated struct Letters: Codable, Equatable, Sendable {
        var set: String

        enum CodingKeys: String, CodingKey {
            case set
        }

        nonisolated init(set: String = LevelConfig.offlineFallbackSet) {
            self.set = set
        }

        /// See `Floor.init(from:)` — absent means "derive from the level folder".
        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            set = try c.decodeIfPresent(String.self, forKey: .set) ?? ""
        }
    }

    enum CodingKeys: String, CodingKey {
        case name
        case order
        case color
        case sprite
        case artifact
        case treasure
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
        case floor
        case letters
    }

    /// Art set for `LevelConfig.fallback`, used only when the bundled config cannot
    /// be read at all. Real levels never consult it — they derive from their folder.
    static let offlineFallbackSet = "1-tython"

    /// Fills in whatever the level's YAML left out, from the level's folder name.
    ///
    /// A level's art is named after its folder, so `floor.set`, `letters.set` and the
    /// level-select planet sprite are all derivable. Levels only spell them out to
    /// deviate — e.g. to share another level's tiles.
    mutating func applyDerivedAssets(levelID: String) {
        if floor.set.isEmpty { floor.set = levelID }
        if letters.set.isEmpty { letters.set = levelID }
        if sprite == nil { sprite = Self.defaultPlanetSprite(levelID: levelID) }
    }

    /// The level-select planet sprite implied by a level's folder.
    static func defaultPlanetSprite(levelID: String) -> SpriteConfig {
        SpriteConfig(
            root: LevelAssetPaths.root(set: levelID, .planet),
            chromaKey: "#000000",
            chromaKeyTolerance: 2,
            animations: [
                "idle": .sheet(
                    sheet: LevelAssetPaths.basename(set: levelID, .planet, .spritesheet),
                    atlas: LevelAssetPaths.basename(set: levelID, .planet, .atlas)
                )
            ]
        )
    }

    static let fallbackFloor = Floor()
    static let fallbackLetters = Letters()

    nonisolated static let fallback = LevelConfig(
        name: "Level 1",
        order: 0,
        color: fallbackColor,
        sprite: nil,
        artifact: fallbackArtifact,
        music: "level",
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
            partitionGateChance: 0.8
        ),
        enemies: .init(types: ["spider"], spawnChancePerRoom: 0.8),
        pickups: .init(
            health: .init(spawnChancePerRoom: 0.8),
            energy: .init(spawnChancePerRoom: 0.8)
        ),
        pit: .fallback,
        gate: .fallback,
        floor: fallbackFloor,
        letters: fallbackLetters
    )

    /// World interaction FX synthesized from gate config (`gate_opened`).
    var worldFx: SoundEffectTable {
        var events: [String: String] = [:]
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
        treasure: String? = nil,
        music: String? = nil,
        gameMusic: GameMusicConfig = .fallback,
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
        gate: GateConfig = .fallback,
        floor: Floor = LevelConfig.fallbackFloor,
        letters: Letters = LevelConfig.fallbackLetters
    ) {
        self.name = name
        self.order = order
        self.color = color
        self.sprite = sprite
        self.artifact = artifact
        self.treasure = treasure
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
        self.floor = floor
        self.letters = letters
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
        treasure = Self.normalizedOptionalID(
            try container.decodeIfPresent(String.self, forKey: .treasure)
        )
        music = try container.decodeIfPresent(String.self, forKey: .music)
        gameMusic = try container.decodeIfPresent(GameMusicConfig.self, forKey: .gameMusic) ?? .fallback
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
        gate = try GateConfig(from: decoder, container: container)
        // Absent blocks decode with an empty set, which applyDerivedAssets fills from
        // the level folder. Using fallbackFloor/fallbackLetters here would hand the
        // level another level's art without saying so.
        floor = try container.decodeIfPresent(Floor.self, forKey: .floor) ?? Floor(set: "")
        letters = try container.decodeIfPresent(Letters.self, forKey: .letters) ?? Letters(set: "")
    }

    func validate() throws {
        guard letterSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidLetterSoundRepeat(letterSoundRepeatSeconds)
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
        guard room.partitionGateChance >= 0, room.partitionGateChance <= 1 else {
            throw WorldSeedError.invalidRoomPartitionGateChance(room.partitionGateChance)
        }
        guard !floor.set.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorldSeedError.emptyFloorSet
        }
        guard floor.decorProb >= 0, floor.decorProb <= 1 else {
            throw WorldSeedError.invalidDecorProb(floor.decorProb)
        }
        guard !letters.set.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorldSeedError.emptyLetterSet
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
            partitionGateChance: Double = 0.8
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
                    partitionGateChance: partitionGateChance
                )
            )
        }
    }

    /// Per-room generation knobs (sizes, pit/gate chances, etc.).
    nonisolated struct RoomParams: Codable, Equatable, Sendable {
        var minRoomSize: Int
        var maxRoomSize: Int
        /// Probability that a room contains a pit (at most one pit area per room).
        var pitChance: Double
        /// Expected pit area size in tiles (clamped to `1...pitMaxSize`).
        var pitMeanSize: Double
        /// Maximum pit area size in tiles.
        var pitMaxSize: Int
        /// Probability that a sealed shared-wall segment becomes a shortcut gate.
        var partitionGateChance: Double

        enum CodingKeys: String, CodingKey {
            case minRoomSize = "min_room_size"
            case maxRoomSize = "max_room_size"
            case pitChance = "pit_chance"
            case pitMeanSize = "pit_mean_size"
            case pitMaxSize = "pit_max_size"
            case partitionGateChance = "partition_gate_chance"
        }

        nonisolated init(
            minRoomSize: Int = 4,
            maxRoomSize: Int = 12,
            pitChance: Double,
            pitMeanSize: Double = 2,
            pitMaxSize: Int = 5,
            partitionGateChance: Double = 0.8
        ) {
            self.minRoomSize = minRoomSize
            self.maxRoomSize = maxRoomSize
            self.pitChance = pitChance
            self.pitMeanSize = pitMeanSize
            self.pitMaxSize = pitMaxSize
            self.partitionGateChance = partitionGateChance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            minRoomSize = try container.decodeIfPresent(Int.self, forKey: .minRoomSize) ?? 4
            maxRoomSize = try container.decodeIfPresent(Int.self, forKey: .maxRoomSize) ?? 12
            pitChance = try container.decode(Double.self, forKey: .pitChance)
            pitMeanSize = try container.decodeIfPresent(Double.self, forKey: .pitMeanSize) ?? 2
            pitMaxSize = try container.decodeIfPresent(Int.self, forKey: .pitMaxSize) ?? 5
            partitionGateChance = try container.decodeIfPresent(
                Double.self, forKey: .partitionGateChance
            ) ?? 0.8
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
                try ConfigStore.data(at: ConfigPath.levelBase(parentName))
            },
            fileLabel: path.description,
            levelID: levelID(forResourceNamed: name),
            wordCatalog: wordCatalog,
            letterCatalog: letterCatalog
        )
    }

    /// The level folder a config's art should be derived from.
    ///
    /// `_defaults` is a shared base rather than a level, so it borrows the first
    /// level's art: it only ever renders before a level has been chosen.
    private static func levelID(forResourceNamed name: String) -> String? {
        guard name == ConfigPath.levelDefaults.basename else { return name }
        return LevelCatalog.levelIDs().min()
    }

    /// Decodes YAML, resolving `inherits:` via `parentDataNamed` when provided (or required).
    /// Shared catalogs resolve gate words / wall letters from bundled YAML (or fallbacks).
    static func decode(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)? = nil,
        fileLabel: String = "level",
        levelID: String? = nil,
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
            if let levelID { level.applyDerivedAssets(levelID: levelID) }
            let words = try wordCatalog ?? Self.loadWordCatalog()
            let letters = try letterCatalog ?? Self.loadLetterCatalog()
            try level.pit.resolveWords(from: words)
            try level.gate.resolveMinigames(wordCatalog: words, letterCatalog: letters)
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

    /// Test/helper entry for inline YAML. `levelID` stands in for the level folder that
    /// art would otherwise be derived from, so callers testing unrelated keys can omit it.
    static func decode(
        from yaml: String,
        levelID: String = offlineFallbackSet,
        wordCatalog: WordCatalog? = nil,
        letterCatalog: LetterCatalog? = nil
    ) throws -> LevelConfig {
        try decode(
            from: Data(yaml.utf8),
            levelID: levelID,
            wordCatalog: wordCatalog,
            letterCatalog: letterCatalog
        )
    }

    /// Test/helper entry that resolves `inherits:` against in-memory parent YAML documents.
    static func decode(
        from yaml: String,
        parents: [String: String],
        levelID: String = offlineFallbackSet,
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
            levelID: levelID,
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

/// A playable level discovered from `Resources/Levels/<id>/`.
nonisolated struct LevelDescriptor: Equatable, Sendable {
    let resourceName: String
    let displayName: String
    let order: Int
    /// Hex fill for the level-select planet sprite.
    let color: String
    /// Level-select planet art from the level YAML `sprite:` block.
    let sprite: SpriteConfig?
    /// Item id for this level's treasure part, shown in the inventory once earned.
    let treasure: String?
    /// SF Symbol awarded on completion; the inventory glyph fallback.
    let artifact: String
}

nonisolated enum LevelCatalog {
    static let subdirectory = ConfigPath.levelRoot

    static func loadFromBundle(
        withExtension ext: String = "yaml"
    ) -> [LevelDescriptor] {
        return levelIDs().compactMap { resourceName -> LevelDescriptor? in
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
                    sprite: level.sprite,
                    treasure: level.treasure,
                    artifact: level.artifact
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

    /// Every directory under `Levels/` is a playable level, so adding one needs no code
    /// change. Names beginning with `_` are shared config (`_defaults.yaml`), not levels.
    static func levelIDs() -> [String] {
        guard let root = Bundle.main.resourceURL?
            .appendingPathComponent(subdirectory, isDirectory: true) else { return [] }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return entries.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            guard isDirectory == true else { return nil }
            let name = url.lastPathComponent
            return name.hasPrefix("_") ? nil : name
        }
    }
}

// MARK: - GateConfig Decodable (private DTO)

extension GateConfig {
    /// Decodes the `gate:` keyed block or falls back to `.fallback`.
    init(
        from decoder: Decoder,
        container: KeyedDecodingContainer<LevelConfig.CodingKeys>
    ) throws {
        guard container.contains(.gate) else {
            self = .fallback
            return
        }
        let dto = try container.decode(GateConfigDTO.self, forKey: .gate)
        fx = dto.fx ?? SoundEffectTable(events: ["opened": "gate-open"])
        guard let entries = dto.minigames, !entries.isEmpty else {
            throw WorldSeedError.decodeFailed("gate.minigames must not be empty")
        }
        minigames = try entries.map { entry in
            switch entry.type {
            case "spelling":
                return .spelling(GateSpellingConfig(
                    timerSeconds: entry.timerSeconds ?? GateSpellingConfig.fallback.timerSeconds,
                    fx: entry.fx ?? SoundEffectTable(),
                    numPaddingLetters: entry.numPaddingLetters
                        ?? GateSpellingConfig.fallback.numPaddingLetters,
                    wordIDs: entry.words?.map { $0.lowercased() },
                    words: [],
                    music: entry.music
                ))
            case "letter_match":
                return .letterMatch(GateLetterMatchConfig(
                    timerSeconds: entry.timerSeconds
                        ?? GateLetterMatchConfig.fallback.timerSeconds,
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
            default:
                throw WorldSeedError.decodeFailed(
                    "Unknown gate minigame type: '\(entry.type)'"
                )
            }
        }
    }
}

private struct GateConfigDTO: Decodable {
    var fx: SoundEffectTable?
    var minigames: [GateMinigameDTO]?
}

private struct GateMinigameDTO: Decodable {
    var type: String
    var timerSeconds: Double?
    var fx: SoundEffectTable?
    var music: String?
    var numPaddingLetters: Int?
    var words: [String]?
    var incorrectReplayDelaySeconds: Double?
    var letterCountMin: Int?
    var letterCountMax: Int?
    var letters: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case timerSeconds = "timer_seconds"
        case fx
        case music
        case numPaddingLetters = "num_padding_letters"
        case words
        case incorrectReplayDelaySeconds = "incorrect_replay_delay_seconds"
        case letterCountMin = "letter_count_min"
        case letterCountMax = "letter_count_max"
        case letters
    }
}
