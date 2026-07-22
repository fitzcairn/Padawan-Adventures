import Testing
@testable import Padawan_Adventures

struct LevelConfigTests {
    @Test func decodesLevelYAML() throws {
        let yaml = """
        width: 100
        height: 100
        algorithm: rooms_doors
        room_count: 100
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 12
          pit_chance: 0.2
          pit_mean_size: 2
          pit_max_size: 5
          wall_destructible_chance: 0.8
          gate_chance: 0.5
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.8
        """
        let level = try LevelConfig.decode(from: yaml)
        #expect(level.width == 100)
        #expect(level.height == 100)
        #expect(level.algorithm == "rooms_doors")
        #expect(level.roomCount == 100)
        #expect(level.corridorWidth == 2)
        #expect(level.room.minRoomSize == 4)
        #expect(level.room.maxRoomSize == 12)
        #expect(level.room.pitChance == 0.2)
        #expect(level.room.pitMeanSize == 2)
        #expect(level.room.pitMaxSize == 5)
        #expect(level.room.wallDestructibleChance == 0.8)
        #expect(level.room.gateChance == 0.5)
        #expect(level.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(level.pickups?.energy?.spawnChancePerRoom == 0.8)
    }

    @Test func worldYAMLAllowsMissingGenerationAndMapSize() throws {
        let yaml = """
        version: 1
        seed: time
        world:
          stories: 1
        enemies:
          type: grunt
          spawn_chance_per_room: 0.8
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.seed == nil)
        #expect(config.world.width == LevelConfig.fallback.width)
        #expect(config.world.height == LevelConfig.fallback.height)
        #expect(config.generation == LevelConfig.fallback.generation)
        try config.validate()
    }
}
