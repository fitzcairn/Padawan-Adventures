import Foundation

struct WorldSeedConfig: Codable, Equatable, Sendable {
    var version: Int
    var seed: UInt64
    var world: WorldSize
    var generation: GenerationParams
    var player: PlayerConfig
    var extensions: [String: String]?

    enum CodingKeys: String, CodingKey {
        case version
        case seed
        case world
        case generation
        case player
        case extensions
    }

    init(
        version: Int,
        seed: UInt64,
        world: WorldSize,
        generation: GenerationParams,
        player: PlayerConfig,
        extensions: [String: String]?
    ) {
        self.version = version
        self.seed = seed
        self.world = world
        self.generation = generation
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
        player = try container.decode(PlayerConfig.self, forKey: .player)
        extensions = try container.decodeIfPresent([String: String].self, forKey: .extensions)
    }

    struct WorldSize: Codable, Equatable, Sendable {
        var width: Int
        var height: Int
        var stories: Int
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
            minRoomSize: Int = 5,
            maxRoomSize: Int = 10,
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
            minRoomSize = try container.decodeIfPresent(Int.self, forKey: .minRoomSize) ?? 5
            maxRoomSize = try container.decodeIfPresent(Int.self, forKey: .maxRoomSize) ?? 10
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
    }
}

enum WorldSeedError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidStoryCount(Int)
    case worldTooSmall
    case missingResource
    case decodeFailed
}
