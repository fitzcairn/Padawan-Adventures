import Foundation

nonisolated struct WorldSeedConfig: Codable, Equatable, Sendable {
    var version: Int
    /// Fixed seed for deterministic worlds. `nil` means resolve from the current time at generation.
    var seed: UInt64?
    var world: WorldSize
    var generation: GenerationParams
    var display: DisplayParams
    var enemies: EnemiesSpawnConfig?
    var pickups: PickupsSpawnConfig?
    var extensions: [String: String]?
    /// World-level event key → sound track basename (`Resources/Audio/FX/`).
    var fx: SoundEffectTable

    enum CodingKeys: String, CodingKey {
        case version
        case seed
        case world
        case generation
        case display
        case enemies
        case pickups
        case extensions
        case fx
    }

    nonisolated init(
        version: Int,
        seed: UInt64? = nil,
        world: WorldSize,
        generation: GenerationParams,
        display: DisplayParams = .default,
        enemies: EnemiesSpawnConfig? = nil,
        pickups: PickupsSpawnConfig? = nil,
        extensions: [String: String]?,
        fx: SoundEffectTable = .empty
    ) {
        self.version = version
        self.seed = seed
        self.world = world
        self.generation = generation
        self.display = display
        self.enemies = enemies
        self.pickups = pickups
        self.extensions = extensions
        self.fx = fx
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        seed = try Self.decodeSeed(from: container)
        world = try container.decode(WorldSize.self, forKey: .world)
        // Prefer level YAML at load time; embedded `generation:` remains for tests / legacy.
        generation = try container.decodeIfPresent(GenerationParams.self, forKey: .generation)
            ?? LevelConfig.fallback.generation
        display = try container.decodeIfPresent(DisplayParams.self, forKey: .display) ?? .default
        // Legacy `player:` block in world.yaml is ignored; see player.yaml.
        enemies = try container.decodeIfPresent(EnemiesSpawnConfig.self, forKey: .enemies)
        pickups = try container.decodeIfPresent(PickupsSpawnConfig.self, forKey: .pickups)
        extensions = try container.decodeIfPresent([String: String].self, forKey: .extensions)
        fx = try container.decodeIfPresent(SoundEffectTable.self, forKey: .fx) ?? .empty
    }

    /// Resolves a concrete RNG seed. Time-based seeds use milliseconds since epoch.
    func resolvedSeed(at date: Date = Date()) -> UInt64 {
        if let seed { return seed }
        let millis = date.timeIntervalSince1970 * 1000
        let value = UInt64(millis.rounded(.down))
        return value == 0 ? 1 : value
    }

    private static func decodeSeed(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UInt64? {
        guard container.contains(.seed) else { return nil }
        if let decodedSeed = try? container.decode(UInt64.self, forKey: .seed) {
            return decodedSeed
        }
        if let decodedSeed = try? container.decode(Int.self, forKey: .seed) {
            return UInt64(decodedSeed)
        }
        let token = try container.decode(String.self, forKey: .seed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard token == "time" else {
            throw WorldSeedError.decodeFailed
        }
        return nil
    }

    nonisolated struct WorldSize: Codable, Equatable, Sendable {
        var width: Int
        var height: Int
        var stories: Int

        enum CodingKeys: String, CodingKey {
            case width
            case height
            case stories
        }

        nonisolated init(width: Int, height: Int, stories: Int) {
            self.width = width
            self.height = height
            self.stories = stories
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Width/height prefer level YAML; world.yaml may omit them.
            width = try container.decodeIfPresent(Int.self, forKey: .width)
                ?? LevelConfig.fallback.width
            height = try container.decodeIfPresent(Int.self, forKey: .height)
                ?? LevelConfig.fallback.height
            stories = try container.decode(Int.self, forKey: .stories)
        }
    }

    /// On-screen isometric tile footprint (zoom).
    nonisolated struct DisplayParams: Codable, Equatable, Sendable {
        var tileWidth: Int
        var tileHeight: Int
        var wallHeight: Int?
        var storyHeight: Int?

        nonisolated static let `default` = DisplayParams(tileWidth: 40, tileHeight: 40)

        enum CodingKeys: String, CodingKey {
            case tileWidth = "tile_width"
            case tileHeight = "tile_height"
            case wallHeight = "wall_height"
            case storyHeight = "story_height"
        }

        nonisolated init(
            tileWidth: Int = 40,
            tileHeight: Int = 40,
            wallHeight: Int? = nil,
            storyHeight: Int? = nil
        ) {
            self.tileWidth = tileWidth
            self.tileHeight = tileHeight
            self.wallHeight = wallHeight
            self.storyHeight = storyHeight
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tileWidth = try container.decodeIfPresent(Int.self, forKey: .tileWidth) ?? 40
            tileHeight = try container.decodeIfPresent(Int.self, forKey: .tileHeight) ?? 40
            wallHeight = try container.decodeIfPresent(Int.self, forKey: .wallHeight)
            storyHeight = try container.decodeIfPresent(Int.self, forKey: .storyHeight)
        }

        func makeIsometricConfig() -> IsometricConfig {
            let width = CGFloat(max(tileWidth, 1))
            let height = CGFloat(max(tileHeight, 1))
            let wall = CGFloat(wallHeight ?? max(tileWidth, tileHeight))
            let story = CGFloat(storyHeight ?? max(tileWidth, tileHeight))
            return IsometricConfig(
                tileWidth: width,
                tileHeight: height,
                wallHeight: max(wall, 1),
                storyHeight: max(story, 1),
                maxStories: 1
            )
        }
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
        var type: String
        var spawnChancePerRoom: Double

        enum CodingKeys: String, CodingKey {
            case type
            case spawnChancePerRoom = "spawn_chance_per_room"
        }

        nonisolated init(type: String, spawnChancePerRoom: Double) {
            self.type = type
            self.spawnChancePerRoom = spawnChancePerRoom
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

    func validate() throws {
        guard version == 1 else {
            throw WorldSeedError.unsupportedVersion(version)
        }
        guard world.stories == 1 else {
            throw WorldSeedError.invalidStoryCount(world.stories)
        }
        guard world.width > 4, world.height > 4 else {
            throw WorldSeedError.worldTooSmall
        }
        guard display.tileWidth > 0, display.tileHeight > 0 else {
            throw WorldSeedError.invalidTileSize
        }
        guard generation.corridorWidth >= 2 else {
            throw WorldSeedError.corridorTooNarrow(generation.corridorWidth)
        }
        guard generation.room.minRoomSize >= 2 else {
            throw WorldSeedError.roomTooNarrow(generation.room.minRoomSize)
        }
        guard generation.room.maxRoomSize >= generation.room.minRoomSize else {
            throw WorldSeedError.invalidRoomSizeRange
        }
        guard generation.room.pitChance >= 0, generation.room.pitChance <= 1 else {
            throw WorldSeedError.invalidRoomPitChance(generation.room.pitChance)
        }
        guard generation.room.pitMaxSize >= 1 else {
            throw WorldSeedError.invalidRoomPitSize(
                mean: generation.room.pitMeanSize,
                max: generation.room.pitMaxSize
            )
        }
        guard generation.room.pitMeanSize >= 1,
              generation.room.pitMeanSize <= Double(generation.room.pitMaxSize) else {
            throw WorldSeedError.invalidRoomPitSize(
                mean: generation.room.pitMeanSize,
                max: generation.room.pitMaxSize
            )
        }
        guard generation.room.wallDestructibleChance >= 0,
              generation.room.wallDestructibleChance <= 1 else {
            throw WorldSeedError.invalidRoomWallDestructibleChance(generation.room.wallDestructibleChance)
        }
        guard generation.room.gateChance >= 0, generation.room.gateChance <= 1 else {
            throw WorldSeedError.invalidRoomGateChance(generation.room.gateChance)
        }
        if let enemies {
            guard !enemies.type.isEmpty else {
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
    }

    private static func validatePickupChance(_ chance: Double?, kind: PickupKind) throws {
        guard let chance else { return }
        guard chance >= 0, chance <= 1 else {
            throw WorldSeedError.invalidPickupSpawnChance(kind: kind, chance: chance)
        }
    }
}

nonisolated enum WorldSeedError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidStoryCount(Int)
    case worldTooSmall
    case invalidTileSize
    case corridorTooNarrow(Int)
    case roomTooNarrow(Int)
    case invalidRoomSizeRange
    case invalidRoomPitChance(Double)
    case invalidRoomPitSize(mean: Double, max: Int)
    case invalidRoomWallDestructibleChance(Double)
    case invalidRoomGateChance(Double)
    case invalidEnemyType
    case invalidEnemySpawnChance(Double)
    case invalidPickupSpawnChance(kind: PickupKind, chance: Double)
    case missingResource
    case decodeFailed
}
