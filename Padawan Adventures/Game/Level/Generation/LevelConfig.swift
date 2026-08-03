import Foundation
import Yams

/// Per-entry pit spelling-hop settings under `pit.minigames` with `type: spelling`.
/// Vocabulary lives in shared `Resources/Config/Vocab/words.yaml`; levels may optionally subset via `words: [id, …]`.
nonisolated struct PitPuzzleConfig: Equatable, Sendable {
    /// Relative pick weight within `pit.minigames`.
    var weight: Double
    /// Extra random letters beyond the chosen word (total sprites = word length + this).
    var numPaddingLetters: Int
    /// Optional subset of shared catalog ids (`nil` = use the full catalog).
    var wordIDs: [String]?
    /// Resolved vocabulary (sorted by word). Populated via `resolveWords(from:)`.
    var words: [GateWord]

    nonisolated static let fallback = PitPuzzleConfig(
        numPaddingLetters: 6,
        words: WordCatalog.fallback.words.filter { ["cat", "dog", "star"].contains($0.word) }
    )

    nonisolated init(
        weight: Double = 1,
        numPaddingLetters: Int = 6,
        wordIDs: [String]? = nil,
        words: [GateWord]
    ) {
        self.weight = weight
        self.numPaddingLetters = numPaddingLetters
        self.wordIDs = wordIDs?.map { $0.lowercased() }
        self.words = GateSpellingConfig.normalizedWords(words)
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
        guard numPaddingLetters >= 0 else {
            throw WorldSeedError.invalidPitWords
        }
        try CatalogValidators.validateWordEntries(
            words,
            emptyError: .invalidPitWords,
            invalidEntryError: .invalidPitWords
        )
    }
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
    /// Multiplier on combat letter spawn frequency vs derived baseline (`1.0` = unchanged).
    var combatLetterSpawnRate: Double
    /// Casing for combat projectile / cue letters.
    var combatLetterCase: CombatLetterCase
    var width: Int
    var height: Int
    var algorithm: String
    var roomCount: Int
    var room: RoomParams
    var enemies: EnemiesSpawnConfig?
    var pickups: PickupsSpawnConfig?
    /// Pit minigame variants + weights for this level.
    var pit: PitConfig
    var gate: GateConfig
    /// Combat minigame variants + weights for this level.
    var combat: CombatConfig
    /// Per-level baked floor tile set (`Levels/{set}/{set}-floor-*`).
    var floor: Floor
    /// Per-level baked letter glyph set (`Levels/{set}/{set}-letters-*`).
    var letters: Letters

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
        case combatLetterSpawnRate = "combat_letter_spawn_rate"
        case combatLetterCase = "combat_letter_case"
        case width
        case height
        case algorithm
        case roomCount = "room_count"
        case room
        case enemies
        case pickups
        case pit
        case gate
        case combat
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
        combatLetterSpawnRate: 1.0,
        combatLetterCase: .upper,
        width: 100,
        height: 100,
        algorithm: "rooms_doors",
        roomCount: 100,
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
        combat: .fallback,
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
        combatLetterSpawnRate: Double = 1.0,
        combatLetterCase: CombatLetterCase = .upper,
        width: Int,
        height: Int,
        algorithm: String,
        roomCount: Int,
        room: RoomParams,
        enemies: EnemiesSpawnConfig? = nil,
        pickups: PickupsSpawnConfig? = nil,
        pit: PitConfig = .fallback,
        gate: GateConfig = .fallback,
        combat: CombatConfig = .fallback,
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
        self.combatLetterSpawnRate = combatLetterSpawnRate
        self.combatLetterCase = combatLetterCase
        self.width = width
        self.height = height
        self.algorithm = algorithm
        self.roomCount = roomCount
        self.room = room
        self.enemies = enemies
        self.pickups = pickups
        self.pit = pit
        self.gate = gate
        self.combat = combat
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
        combatLetterSpawnRate = try container.decodeIfPresent(
            Double.self,
            forKey: .combatLetterSpawnRate
        ) ?? Self.fallback.combatLetterSpawnRate
        if let rawCase = try container.decodeIfPresent(String.self, forKey: .combatLetterCase) {
            let trimmed = rawCase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let parsed = CombatLetterCase(rawValue: trimmed) else {
                throw WorldSeedError.invalidCombatLetterCase(rawCase)
            }
            combatLetterCase = parsed
        } else {
            combatLetterCase = Self.fallback.combatLetterCase
        }
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        roomCount = try container.decode(Int.self, forKey: .roomCount)
        room = try container.decode(RoomParams.self, forKey: .room)
        enemies = try container.decodeIfPresent(EnemiesSpawnConfig.self, forKey: .enemies)
        pickups = try container.decodeIfPresent(PickupsSpawnConfig.self, forKey: .pickups)
        pit = try PitConfig(from: decoder, container: container)
        gate = try GateConfig(from: decoder, container: container)
        combat = try CombatConfig(from: decoder, container: container)
        // Absent blocks decode with an empty set, which applyDerivedAssets fills from
        // the level folder. Using fallbackFloor/fallbackLetters here would hand the
        // level another level's art without saying so.
        floor = try container.decodeIfPresent(Floor.self, forKey: .floor) ?? Floor(set: "")
        letters = try container.decodeIfPresent(Letters.self, forKey: .letters) ?? Letters(set: "")
    }

    func validate() throws {
        try GenerationParamsValidator.validate(
            algorithm: algorithm,
            width: width,
            height: height,
            room: room,
            floorSet: floor.set,
            decorProb: floor.decorProb,
            cohesion: floor.cohesion,
            enemies: enemies,
            pickups: pickups
        )
        guard letterSoundRepeatSeconds > 0 else {
            throw WorldSeedError.invalidLetterSoundRepeat(letterSoundRepeatSeconds)
        }
        guard combatLetterSpawnRate > 0 else {
            throw WorldSeedError.invalidCombatLetterSpawnRate(combatLetterSpawnRate)
        }
        guard !letters.set.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorldSeedError.emptyLetterSet
        }
        try pit.validate()
        try gate.validate()
        try combat.validate()
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
            room: room
        )
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
            try level.combat.resolveLetters(from: letters)
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

extension LevelConfig {
    /// Floor tile set reference and decor sprinkle probability.
    nonisolated struct Floor: Codable, Equatable, Sendable {
        var set: String
        var decorProb: Double
        /// 0 = legacy per-cell variety, 1 = maximal patching. Default 0.75.
        var cohesion: Double

        enum CodingKeys: String, CodingKey {
            case set
            case decorProb = "decor_prob"
            case cohesion
        }

        nonisolated init(
            set: String = LevelConfig.offlineFallbackSet,
            decorProb: Double = 0.06,
            cohesion: Double = 0.75
        ) {
            self.set = set
            self.decorProb = decorProb
            self.cohesion = cohesion
        }

        /// An absent `set:` decodes empty and is filled in from the level's folder
        /// name by `LevelConfig.decode`. Defaulting to a real set here would silently
        /// give a level another level's art.
        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            set = try c.decodeIfPresent(String.self, forKey: .set) ?? ""
            decorProb = try c.decodeIfPresent(Double.self, forKey: .decorProb) ?? 0.06
            cohesion = try c.decodeIfPresent(Double.self, forKey: .cohesion) ?? 0.75
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

    nonisolated struct GenerationParams: Codable, Equatable, Sendable {
        var algorithm: String
        var roomCount: Int
        var room: RoomParams

        enum CodingKeys: String, CodingKey {
            case algorithm
            case roomCount = "room_count"
            case room
        }

        nonisolated init(
            algorithm: String,
            roomCount: Int,
            room: RoomParams
        ) {
            self.algorithm = algorithm
            self.roomCount = roomCount
            self.room = room
        }

        /// Convenience for tests / fallbacks.
        nonisolated init(
            algorithm: String,
            roomCount: Int,
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
}
