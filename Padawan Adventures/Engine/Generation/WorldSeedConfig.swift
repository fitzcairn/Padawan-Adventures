import Foundation

struct WorldSeedConfig: Codable, Equatable, Sendable {
    var version: Int
    var seed: UInt64
    var world: WorldSize
    var generation: GenerationParams
    var display: DisplayParams
    var player: PlayerConfig
    var extensions: [String: String]?

    enum CodingKeys: String, CodingKey {
        case version
        case seed
        case world
        case generation
        case display
        case player
        case extensions
    }

    init(
        version: Int,
        seed: UInt64,
        world: WorldSize,
        generation: GenerationParams,
        display: DisplayParams = .default,
        player: PlayerConfig,
        extensions: [String: String]?
    ) {
        self.version = version
        self.seed = seed
        self.world = world
        self.generation = generation
        self.display = display
        self.player = player
        self.extensions = extensions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        if let decodedSeed = try? container.decode(UInt64.self, forKey: .seed) {
            seed = decodedSeed
        } else {
            seed = UInt64(try container.decode(Int.self, forKey: .seed))
        }
        world = try container.decode(WorldSize.self, forKey: .world)
        generation = try container.decode(GenerationParams.self, forKey: .generation)
        display = try container.decodeIfPresent(DisplayParams.self, forKey: .display) ?? .default
        player = try container.decode(PlayerConfig.self, forKey: .player)
        extensions = try container.decodeIfPresent([String: String].self, forKey: .extensions)
    }

    struct WorldSize: Codable, Equatable, Sendable {
        var width: Int
        var height: Int
        var stories: Int
    }

    /// On-screen isometric tile footprint (zoom).
    struct DisplayParams: Codable, Equatable, Sendable {
        var tileWidth: Int
        var tileHeight: Int
        var wallHeight: Int?
        var storyHeight: Int?

        static let `default` = DisplayParams(tileWidth: 40, tileHeight: 40)

        enum CodingKeys: String, CodingKey {
            case tileWidth = "tile_width"
            case tileHeight = "tile_height"
            case wallHeight = "wall_height"
            case storyHeight = "story_height"
        }

        init(
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
                storyHeight: max(story, 1)
            )
        }
    }

    struct GenerationParams: Codable, Equatable, Sendable {
        var algorithm: String
        var roomCount: Int
        var corridorWidth: Int
        var minRoomSize: Int
        var maxRoomSize: Int
        var pitChance: Double
        var wallDestructibleChance: Double
        var rampCount: Int
        var ladderCount: Int
        var slideCount: Int
        var doorCount: Int

        enum CodingKeys: String, CodingKey {
            case algorithm
            case roomCount = "room_count"
            case corridorWidth = "corridor_width"
            case minRoomSize = "min_room_size"
            case maxRoomSize = "max_room_size"
            case pitChance = "pit_chance"
            case wallDestructibleChance = "wall_destructible_chance"
            case rampCount = "ramp_count"
            case ladderCount = "ladder_count"
            case slideCount = "slide_count"
            case doorCount = "door_count"
        }

        init(
            algorithm: String,
            roomCount: Int,
            corridorWidth: Int,
            minRoomSize: Int = 4,
            maxRoomSize: Int = 12,
            pitChance: Double,
            wallDestructibleChance: Double,
            rampCount: Int,
            ladderCount: Int,
            slideCount: Int,
            doorCount: Int
        ) {
            self.algorithm = algorithm
            self.roomCount = roomCount
            self.corridorWidth = corridorWidth
            self.minRoomSize = minRoomSize
            self.maxRoomSize = maxRoomSize
            self.pitChance = pitChance
            self.wallDestructibleChance = wallDestructibleChance
            self.rampCount = rampCount
            self.ladderCount = ladderCount
            self.slideCount = slideCount
            self.doorCount = doorCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            algorithm = try container.decode(String.self, forKey: .algorithm)
            roomCount = try container.decode(Int.self, forKey: .roomCount)
            corridorWidth = try container.decode(Int.self, forKey: .corridorWidth)
            minRoomSize = try container.decodeIfPresent(Int.self, forKey: .minRoomSize) ?? 4
            maxRoomSize = try container.decodeIfPresent(Int.self, forKey: .maxRoomSize) ?? 12
            pitChance = try container.decode(Double.self, forKey: .pitChance)
            wallDestructibleChance = try container.decode(Double.self, forKey: .wallDestructibleChance)
            rampCount = try container.decode(Int.self, forKey: .rampCount)
            ladderCount = try container.decode(Int.self, forKey: .ladderCount)
            slideCount = try container.decode(Int.self, forKey: .slideCount)
            doorCount = try container.decode(Int.self, forKey: .doorCount)
        }
    }

    struct PlayerConfig: Codable, Equatable, Sendable {
        var letter: String
        var spawn: SpawnCoord?

        struct SpawnCoord: Codable, Equatable, Sendable {
            var x: Int
            var y: Int
            var story: Int
        }
    }

    func validate() throws {
        guard version == 1 else {
            throw WorldSeedError.unsupportedVersion(version)
        }
        guard world.stories == 2 else {
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
        guard generation.minRoomSize >= 2 else {
            throw WorldSeedError.roomTooNarrow(generation.minRoomSize)
        }
        guard generation.maxRoomSize >= generation.minRoomSize else {
            throw WorldSeedError.invalidRoomSizeRange
        }
    }
}

enum WorldSeedError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidStoryCount(Int)
    case worldTooSmall
    case invalidTileSize
    case corridorTooNarrow(Int)
    case roomTooNarrow(Int)
    case invalidRoomSizeRange
    case missingResource
    case decodeFailed
}
