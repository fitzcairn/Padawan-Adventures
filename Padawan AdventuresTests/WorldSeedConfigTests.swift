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
          stories: 2
        generation:
          algorithm: rooms_bsp
          room_count: 6
          corridor_width: 1
          pit_chance: 0.05
          wall_destructible_chance: 0.2
          ramp_count: 2
          ladder_count: 2
          slide_count: 1
          door_count: 4
        player:
          letter: P
          spawn: { x: 3, y: 3, story: 0 }
        extensions: {}
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.version == 1)
        #expect(config.seed == 42)
        #expect(config.world.stories == 2)
        #expect(config.player.letter == "P")
        try config.validate()
    }

    @Test func rejectsInvalidStoryCount() throws {
        let yaml = """
        version: 1
        seed: 1
        world:
          width: 10
          height: 10
          stories: 3
        generation:
          algorithm: rooms_bsp
          room_count: 2
          corridor_width: 1
          pit_chance: 0.0
          wall_destructible_chance: 0.0
          ramp_count: 0
          ladder_count: 0
          slide_count: 0
          door_count: 0
        player:
          letter: P
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(throws: WorldSeedError.invalidStoryCount(3)) {
            try config.validate()
        }
    }
}
