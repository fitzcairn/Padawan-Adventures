import CoreGraphics
import Testing
@testable import Padawan_Adventures

struct WorldSeedConfigTests {
    @Test func decodesSampleYAML() throws {
        let yaml = """
        version: 1
        seed: 42
        world:
          width: 24
          height: 24
          stories: 1
        generation:
          algorithm: rooms_bsp
          room_count: 6
          corridor_width: 2
          pit_chance: 0.05
          wall_destructible_chance: 0.2
          door_count: 4
        player:
          letter: P
          spawn: { x: 3, y: 3, story: 0 }
        extensions: {}
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.version == 1)
        #expect(config.seed == 42)
        #expect(config.world.stories == 1)
        #expect(config.player.letter == "P")
        #expect(config.display.tileWidth == 40)
        #expect(config.display.tileHeight == 40)
        try config.validate()
    }

    @Test func decodesDisplayTileSize() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 1
        display:
          tile_width: 48
          tile_height: 24
          wall_height: 36
        generation:
          algorithm: rooms_doors
          room_count: 2
          corridor_width: 2
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          door_count: 0
        player:
          letter: P
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.display.tileWidth == 48)
        #expect(config.display.tileHeight == 24)
        let iso = config.display.makeIsometricConfig()
        #expect(iso.tileWidth == 48 as CGFloat)
        #expect(iso.tileHeight == 24 as CGFloat)
        #expect(iso.wallHeight == 36 as CGFloat)
        #expect(iso.storyHeight == 48 as CGFloat)
    }

    @Test func rejectsInvalidStoryCount() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 2
        generation:
          algorithm: rooms_bsp
          room_count: 2
          corridor_width: 2
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          door_count: 0
        player:
          letter: P
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.invalidStoryCount(2)) {
            try config.validate()
        }
    }

    @Test func decodesEnemiesSpawnBlock() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 1
        generation:
          algorithm: rooms_doors
          room_count: 2
          corridor_width: 2
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          door_count: 0
        player:
          letter: P
        enemies:
          type: grunt
          spawn_chance_per_room: 0.8
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.enemies?.type == "grunt")
        #expect(config.enemies?.spawnChancePerRoom == 0.8)
        try config.validate()
    }

    @Test func rejectsInvalidEnemySpawnChance() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 1
        generation:
          algorithm: rooms_doors
          room_count: 2
          corridor_width: 2
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          door_count: 0
        player:
          letter: P
        enemies:
          type: grunt
          spawn_chance_per_room: 1.5
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.invalidEnemySpawnChance(1.5)) {
            try config.validate()
        }
    }

    @Test func decodesPickupsSpawnBlock() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 1
        generation:
          algorithm: rooms_doors
          room_count: 2
          corridor_width: 2
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          door_count: 0
        player:
          letter: P
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.5
          treasure:
            spawn_chance_per_room: 1.0
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(config.pickups?.energy?.spawnChancePerRoom == 0.5)
        #expect(config.pickups?.treasure?.spawnChancePerRoom == 1.0)
        try config.validate()
    }

    @Test func rejectsInvalidPickupSpawnChance() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 1
        generation:
          algorithm: rooms_doors
          room_count: 2
          corridor_width: 2
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          door_count: 0
        player:
          letter: P
        pickups:
          health:
            spawn_chance_per_room: -0.1
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.invalidPickupSpawnChance(kind: .health, chance: -0.1)) {
            try config.validate()
        }
    }

    @Test func rejectsCorridorNarrowerThanTwo() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 1
        generation:
          algorithm: rooms_doors
          room_count: 2
          corridor_width: 1
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          door_count: 0
        player:
          letter: P
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.corridorTooNarrow(1)) {
            try config.validate()
        }
    }
}
