import Foundation
import Yams

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
    var width: Int
    var height: Int
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
    /// Cumulative vocabulary pool for this level's order (weighted toward current level).
    var vocabulary: LevelVocabularyPool
    /// Declared `vocab:` block after inheritance (nil when omitted).
    var vocab: LevelVocabularySpec?
    /// `world.vocabulary.current_level_probability` used to weight pool tiers.
    var currentLevelProbability: Double

    enum CodingKeys: String, CodingKey {
        case name
        case order
        case color
        case sprite
        case artifact
        case treasure
        case world
        case pit
        case gate
        case combat
        case letters
        case vocab
    }

    private enum WorldKeys: String, CodingKey {
        case music
        case widthTiles = "width_tiles"
        case heightTiles = "height_tiles"
        case roomCount = "room_count"
        case room
        case floor
        case enemies
        case pickups
        case vocabulary
    }

    private enum VocabularyKeys: String, CodingKey {
        case currentLevelProbability = "current_level_probability"
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
        width: 100,
        height: 100,
        roomCount: 100,
        room: .init(
            minRoomSize: 4,
            maxRoomSize: 12,
            pitChance: 0.2,
            pitMeanSize: 2,
            pitMaxSize: 5,
            gateProbability: 0.8
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
        letters: fallbackLetters,
        vocabulary: .fallback,
        vocab: nil,
        currentLevelProbability: 0.75
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
        width: Int,
        height: Int,
        roomCount: Int,
        room: RoomParams,
        enemies: EnemiesSpawnConfig? = nil,
        pickups: PickupsSpawnConfig? = nil,
        pit: PitConfig = .fallback,
        gate: GateConfig = .fallback,
        combat: CombatConfig = .fallback,
        floor: Floor = LevelConfig.fallbackFloor,
        letters: Letters = LevelConfig.fallbackLetters,
        vocabulary: LevelVocabularyPool = .fallback,
        vocab: LevelVocabularySpec? = nil,
        currentLevelProbability: Double = 0.75
    ) {
        self.name = name
        self.order = order
        self.color = color
        self.sprite = sprite
        self.artifact = artifact
        self.treasure = treasure
        self.music = music
        self.width = width
        self.height = height
        self.roomCount = roomCount
        self.room = room
        self.enemies = enemies
        self.pickups = pickups
        self.pit = pit
        self.gate = gate
        self.combat = combat
        self.floor = floor
        self.letters = letters
        self.vocabulary = vocabulary
        self.vocab = vocab
        self.currentLevelProbability = currentLevelProbability
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

        let world = try container.nestedContainer(keyedBy: WorldKeys.self, forKey: .world)
        music = try world.decodeIfPresent(String.self, forKey: .music)
        width = try world.decode(Int.self, forKey: .widthTiles)
        height = try world.decode(Int.self, forKey: .heightTiles)
        roomCount = try world.decode(Int.self, forKey: .roomCount)
        room = try world.decode(RoomParams.self, forKey: .room)
        enemies = try world.decodeIfPresent(EnemiesSpawnConfig.self, forKey: .enemies)
        pickups = try world.decodeIfPresent(PickupsSpawnConfig.self, forKey: .pickups)
        floor = try world.decodeIfPresent(Floor.self, forKey: .floor) ?? Floor(set: "")
        if world.contains(.vocabulary) {
            let vocabularyKeys = try world.nestedContainer(
                keyedBy: VocabularyKeys.self,
                forKey: .vocabulary
            )
            currentLevelProbability = try vocabularyKeys.decodeIfPresent(
                Double.self,
                forKey: .currentLevelProbability
            ) ?? 0.75
        } else {
            currentLevelProbability = 0.75
        }

        pit = try PitConfig(from: decoder, container: container)
        gate = try GateConfig(from: decoder, container: container)
        combat = try CombatConfig(from: decoder, container: container)
        letters = try container.decodeIfPresent(Letters.self, forKey: .letters) ?? Letters(set: "")
        vocab = try container.decodeIfPresent(LevelVocabularySpec.self, forKey: .vocab)
        // Filled after decode from `LevelVocabularyCatalog.pool(...)`.
        vocabulary = .empty
    }

    func validate() throws {
        try GenerationParamsValidator.validate(
            width: width,
            height: height,
            room: room,
            floorSet: floor.set,
            decorProb: floor.decorProb,
            cohesion: floor.cohesion,
            enemies: enemies,
            pickups: pickups
        )
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
            case spawnChancePerRoom = "spawn_probability_per_room"
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
            case spawnChancePerRoom = "spawn_probability_per_room"
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
        graphemeCatalog: GraphemeCatalog? = nil,
        vocabularyCatalog: LevelVocabularyCatalog? = nil
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
            graphemeCatalog: graphemeCatalog,
            vocabularyCatalog: vocabularyCatalog
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
    /// Shared catalogs resolve the level vocabulary pool from bundled YAML (or fallbacks).
    static func decode(
        from data: Data,
        parentDataNamed: ((String) throws -> Data)? = nil,
        fileLabel: String = "level",
        levelID: String? = nil,
        wordCatalog: WordCatalog? = nil,
        graphemeCatalog: GraphemeCatalog? = nil,
        vocabularyCatalog: LevelVocabularyCatalog? = nil
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
            let letters = try graphemeCatalog ?? Self.loadGraphemeCatalog()
            let vocabCatalog = try vocabularyCatalog ?? Self.loadVocabularyCatalog()
            level.vocabulary = try vocabCatalog.pool(
                forOrder: level.order,
                probability: level.currentLevelProbability,
                wordCatalog: words,
                graphemeCatalog: letters
            )
            try level.pit.resolveMinigames(from: level.vocabulary)
            try level.gate.resolveMinigames(from: level.vocabulary)
            try level.combat.resolveGraphemes(from: level.vocabulary)
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
        graphemeCatalog: GraphemeCatalog? = nil,
        vocabularyCatalog: LevelVocabularyCatalog? = nil
    ) throws -> LevelConfig {
        try decode(
            from: Data(yaml.utf8),
            levelID: levelID,
            wordCatalog: wordCatalog,
            graphemeCatalog: graphemeCatalog,
            vocabularyCatalog: vocabularyCatalog
        )
    }

    /// Test/helper entry that resolves `inherits:` against in-memory parent YAML documents.
    static func decode(
        from yaml: String,
        parents: [String: String],
        levelID: String = offlineFallbackSet,
        wordCatalog: WordCatalog? = nil,
        graphemeCatalog: GraphemeCatalog? = nil,
        vocabularyCatalog: LevelVocabularyCatalog? = nil
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
            graphemeCatalog: graphemeCatalog,
            vocabularyCatalog: vocabularyCatalog
        )
    }

    private static func loadWordCatalog() throws -> WordCatalog {
        do {
            return try WordCatalog.loadFromBundle()
        } catch ConfigError.missingResource {
            return .fallback
        }
    }

    private static func loadGraphemeCatalog() throws -> GraphemeCatalog {
        do {
            return try GraphemeCatalog.loadFromBundle()
        } catch ConfigError.missingResource {
            return .fallback
        }
    }

    private static func loadVocabularyCatalog() throws -> LevelVocabularyCatalog {
        do {
            return try LevelVocabularyCatalog.loadFromBundle()
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
            case decorProb = "decor_probability"
            case cohesion = "cohesion_fraction"
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
        var roomCount: Int
        var room: RoomParams

        enum CodingKeys: String, CodingKey {
            case roomCount = "room_count"
            case room
        }

        nonisolated init(
            roomCount: Int,
            room: RoomParams
        ) {
            self.roomCount = roomCount
            self.room = room
        }

        /// Convenience for tests / fallbacks.
        nonisolated init(
            roomCount: Int,
            minRoomSize: Int = 4,
            maxRoomSize: Int = 12,
            pitChance: Double,
            pitMeanSize: Double = 2,
            pitMaxSize: Int = 5,
            gateProbability: Double = 0.8
        ) {
            self.init(
                roomCount: roomCount,
                room: RoomParams(
                    minRoomSize: minRoomSize,
                    maxRoomSize: maxRoomSize,
                    pitChance: pitChance,
                    pitMeanSize: pitMeanSize,
                    pitMaxSize: pitMaxSize,
                    gateProbability: gateProbability
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
        /// Probability that a join edge becomes a gated strip (miss → open doorway).
        var gateProbability: Double

        enum CodingKeys: String, CodingKey {
            case minRoomSize = "min_size_tiles"
            case maxRoomSize = "max_size_tiles"
            case pitChance = "pit_probability"
            case pitMeanSize = "pit_mean_size_tiles"
            case pitMaxSize = "pit_max_size_tiles"
            case gateProbability = "gate_probability"
        }

        nonisolated init(
            minRoomSize: Int = 4,
            maxRoomSize: Int = 12,
            pitChance: Double,
            pitMeanSize: Double = 2,
            pitMaxSize: Int = 5,
            gateProbability: Double = 0.8
        ) {
            self.minRoomSize = minRoomSize
            self.maxRoomSize = maxRoomSize
            self.pitChance = pitChance
            self.pitMeanSize = pitMeanSize
            self.pitMaxSize = pitMaxSize
            self.gateProbability = gateProbability
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            minRoomSize = try container.decodeIfPresent(Int.self, forKey: .minRoomSize) ?? 4
            maxRoomSize = try container.decodeIfPresent(Int.self, forKey: .maxRoomSize) ?? 12
            pitChance = try container.decode(Double.self, forKey: .pitChance)
            pitMeanSize = try container.decodeIfPresent(Double.self, forKey: .pitMeanSize) ?? 2
            pitMaxSize = try container.decodeIfPresent(Int.self, forKey: .pitMaxSize) ?? 5
            gateProbability = try container.decodeIfPresent(
                Double.self, forKey: .gateProbability
            ) ?? 0.8
        }
    }
}
