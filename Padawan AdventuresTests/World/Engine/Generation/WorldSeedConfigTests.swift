import CoreGraphics
import Foundation
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.05
            wall_destructible_chance: 0.2
            gate_chance: 0.5
        player:
          letter: P
          spawn: { x: 3, y: 3, story: 0 }
        extensions: {}
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.version == 1)
        #expect(config.seed == 42)
        #expect(config.resolvedSeed() == 42)
        #expect(config.world.stories == 1)
        #expect(config.display.tileWidth == 40)
        #expect(config.display.tileHeight == 40)
        try config.validate()
    }

    @Test func decodesTimeSeedToken() throws {
        let yaml = """
        version: 1
        seed: time
        world:
          width: 24
          height: 24
          stories: 1
        generation:
          algorithm: rooms_doors
          room_count: 6
          corridor_width: 2
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.05
            wall_destructible_chance: 0.2
            gate_chance: 0.5
        """
        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.seed == nil)
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        #expect(config.resolvedSeed(at: date) == 1_700_000_000_500)
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 0.0
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 0.0
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 0.0
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 0.0
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 0.0
        player:
          letter: P
        pickups:
          health:
            spawn_chance_per_room: 0.8
          energy:
            spawn_chance_per_room: 0.5
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.pickups?.health?.spawnChancePerRoom == 0.8)
        #expect(config.pickups?.energy?.spawnChancePerRoom == 0.5)
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 0.0
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

    @Test func rejectsInvalidPitSize() throws {
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.2
            pit_mean_size: 6
            pit_max_size: 5
            wall_destructible_chance: 0.0
            gate_chance: 0.0
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.invalidRoomPitSize(mean: 6, max: 5)) {
            try config.validate()
        }
    }

    @Test func rejectsInvalidGateChance() throws {
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 1.5
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.invalidRoomGateChance(1.5)) {
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
          room:
            min_room_size: 4
            max_room_size: 12
            pit_chance: 0.0
            wall_destructible_chance: 0.0
            gate_chance: 0.0
        player:
          letter: P
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.corridorTooNarrow(1)) {
            try config.validate()
        }
    }
}
