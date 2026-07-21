import Testing
@testable import Padawan_Adventures

struct LevelConfigTests {
    @Test func decodesLevelYAML() throws {
        let yaml = """
        algorithm: rooms_doors
        room_count: 100
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.2
          wall_destructible_chance: 0.8
          door_count: 4
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.algorithm == "rooms_doors")
        #expect(level.roomCount == 100)
        #expect(level.corridorWidth == 2)
        #expect(level.room.minRoomSize == 4)
        #expect(level.room.maxRoomSize == 12)
        #expect(level.room.pitChance == 0.2)
        #expect(level.room.wallDestructibleChance == 0.8)
        #expect(level.room.doorCount == 4)
    }

    @Test func worldYAMLAllowsMissingGeneration() throws {
        let yaml = """
        version: 1
        seed: time
        world:
          width: 24
          height: 24
          stories: 1
        enemies:
          type: grunt
          spawn_chance_per_room: 0.8
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.seed == nil)
        #expect(config.generation == LevelConfig.fallback)
        try config.validate()
    }
}
