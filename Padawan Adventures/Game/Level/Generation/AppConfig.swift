import CoreGraphics
import Foundation

/// App-level knobs from `Resources/Config/app.yaml` (seed, display, stories, Dad mode).
/// Map size, generation, enemies, floors, and puzzle FX live on `LevelConfig`.
nonisolated struct AppConfig: Codable, Equatable, Sendable {
    var version: Int
    /// Fixed seed for deterministic worlds. `nil` means resolve from the current time at generation.
    var seed: UInt64?
    var world: WorldSize
    var display: DisplayParams
    /// 4-digit password that unlocks Dad mode on the level select screen.
    var dadModePassword: String

    enum CodingKeys: String, CodingKey {
        case version
        case seed
        case world
        case display
        case dadModePassword = "dad_mode_password"
    }

    /// Default Dad mode password when omitted from YAML.
    static let defaultDadModePassword = "1234"

    nonisolated init(
        version: Int,
        seed: UInt64? = nil,
        world: WorldSize = WorldSize(stories: 1),
        display: DisplayParams = .default,
        dadModePassword: String = AppConfig.defaultDadModePassword
    ) {
        self.version = version
        self.seed = seed
        self.world = world
        self.display = display
        self.dadModePassword = dadModePassword
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        seed = try Self.decodeSeed(from: container)
        world = try container.decode(WorldSize.self, forKey: .world)
        display = try container.decodeIfPresent(DisplayParams.self, forKey: .display) ?? .default
        dadModePassword = try Self.decodeDadModePassword(from: container)
    }

    private static func decodeDadModePassword(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        guard container.contains(.dadModePassword) else {
            return defaultDadModePassword
        }
        if let value = try? container.decode(String.self, forKey: .dadModePassword) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: .dadModePassword) {
            return String(value)
        }
        throw WorldSeedError.decodeFailed("dad_mode_password must be a string or integer")
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
            throw WorldSeedError.decodeFailed("seed must be an integer or \"time\"")
        }
        return nil
    }

    /// Story count for generated worlds (`width` / `height` come from `LevelConfig`).
    nonisolated struct WorldSize: Codable, Equatable, Sendable {
        var stories: Int

        enum CodingKeys: String, CodingKey {
            case stories
        }

        nonisolated init(stories: Int) {
            self.stories = stories
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stories = try container.decode(Int.self, forKey: .stories)
        }
    }

    /// On-screen isometric tile footprint (zoom) and shared UI display knobs.
    nonisolated struct DisplayParams: Codable, Equatable, Sendable {
        var tileWidth: Int
        var tileHeight: Int
        var wallHeight: Int?
        var storyHeight: Int?
        /// Seconds before overlays auto-dismiss (tap also dismisses). `0` disables auto-dismiss.
        var overlayDismissSeconds: Double

        nonisolated static let `default` = DisplayParams(
            tileWidth: 40,
            tileHeight: 40,
            overlayDismissSeconds: 6
        )

        enum CodingKeys: String, CodingKey {
            case tileWidth = "tile_width"
            case tileHeight = "tile_height"
            case wallHeight = "wall_height"
            case storyHeight = "story_height"
            case overlayDismissSeconds = "overlay_dismiss_seconds"
        }

        nonisolated init(
            tileWidth: Int = 40,
            tileHeight: Int = 40,
            wallHeight: Int? = nil,
            storyHeight: Int? = nil,
            overlayDismissSeconds: Double = 6
        ) {
            self.tileWidth = tileWidth
            self.tileHeight = tileHeight
            self.wallHeight = wallHeight
            self.storyHeight = storyHeight
            self.overlayDismissSeconds = overlayDismissSeconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tileWidth = try container.decodeIfPresent(Int.self, forKey: .tileWidth) ?? 40
            tileHeight = try container.decodeIfPresent(Int.self, forKey: .tileHeight) ?? 40
            wallHeight = try container.decodeIfPresent(Int.self, forKey: .wallHeight)
            storyHeight = try container.decodeIfPresent(Int.self, forKey: .storyHeight)
            overlayDismissSeconds = try container.decodeIfPresent(
                Double.self,
                forKey: .overlayDismissSeconds
            ) ?? 6
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

    func validate() throws {
        guard version == 1 else {
            throw WorldSeedError.unsupportedVersion(version)
        }
        guard world.stories == 1 else {
            throw WorldSeedError.invalidStoryCount(world.stories)
        }
        guard display.tileWidth > 0, display.tileHeight > 0 else {
            throw WorldSeedError.invalidTileSize
        }
    }
}

/// Composed app + level view used by `ProceduralGenerator` and save-compatibility checks.
nonisolated struct WorldGenerationConfig: Equatable, Sendable {
    var seed: UInt64?
    var world: MapSize
    var generation: LevelConfig.GenerationParams
    var enemies: LevelConfig.EnemiesSpawnConfig?
    var pickups: LevelConfig.PickupsSpawnConfig?
    var floorSprites: [String]
    var floorAccentProb: Double
    var cornerSpecialProb: Double

    nonisolated struct MapSize: Equatable, Sendable {
        var width: Int
        var height: Int
        var stories: Int
    }

    nonisolated init(
        seed: UInt64? = nil,
        world: MapSize,
        generation: LevelConfig.GenerationParams,
        enemies: LevelConfig.EnemiesSpawnConfig? = nil,
        pickups: LevelConfig.PickupsSpawnConfig? = nil,
        floorSprites: [String] = LevelConfig.fallback.floorSprites,
        floorAccentProb: Double = LevelConfig.fallbackFloorAccentProb,
        cornerSpecialProb: Double = LevelConfig.fallbackCornerSpecialProb
    ) {
        self.seed = seed
        self.world = world
        self.generation = generation
        self.enemies = enemies
        self.pickups = pickups
        self.floorSprites = floorSprites
        self.floorAccentProb = floorAccentProb
        self.cornerSpecialProb = cornerSpecialProb
    }

    static func compose(app: AppConfig, level: LevelConfig) -> WorldGenerationConfig {
        WorldGenerationConfig(
            seed: app.seed,
            world: MapSize(
                width: level.width,
                height: level.height,
                stories: app.world.stories
            ),
            generation: level.generation,
            enemies: level.enemies,
            pickups: level.pickups,
            floorSprites: level.floorSprites,
            floorAccentProb: level.floorAccentProb,
            cornerSpecialProb: level.cornerSpecialProb
        )
    }

    func resolvedSeed(at date: Date = Date()) -> UInt64 {
        if let seed { return seed }
        let millis = date.timeIntervalSince1970 * 1000
        let value = UInt64(millis.rounded(.down))
        return value == 0 ? 1 : value
    }

    func validate() throws {
        guard world.stories == 1 else {
            throw WorldSeedError.invalidStoryCount(world.stories)
        }
        guard world.width > 4, world.height > 4 else {
            throw WorldSeedError.worldTooSmall
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
    case invalidGateTimer(Double)
    case invalidGatePaddingLetters(Int)
    case invalidGateWords
    case invalidPitTimer(Double)
    case invalidPitWords
    case invalidDestructibleWallTimer(Double)
    case invalidDestructibleWallLetterSoundRepeat(Double)
    case invalidDestructibleWallIncorrectReplayDelay(Double)
    case invalidDestructibleWallLetterCountRange(min: Int, max: Int)
    case invalidDestructibleWallLetters
    case invalidEnemyType
    case invalidEnemySpawnChance(Double)
    case invalidPickupSpawnChance(kind: PickupKind, chance: Double)
    /// Generated map is missing one or more required interactables after retries.
    case missingRequiredInteractables([RequiredInteractable])
    case missingResource
    /// YAML/config decode failed; associated value carries the underlying reason.
    case decodeFailed(String)
    case emptyFloorSprites
    case invalidFloorAccentProb(Double)
    case invalidCornerSpecialProb(Double)
}

/// Interactable kinds every valid map must include at least once.
nonisolated enum RequiredInteractable: String, Equatable, Sendable, CaseIterable {
    case gate
    case pit
    case destructibleWall
    case enemy
}
