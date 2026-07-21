import Testing
@testable import Padawan_Adventures

struct PlayerConfigTests {
    @Test func decodesPlayerYAML() throws {
        let yaml = """
        letter: P
        starting_health: 3
        starting_energy: 2
        """
        let config = try PlayerConfig.decode(from: yaml)
        #expect(config.letter == "P")
        #expect(config.startingHealth == 3)
        #expect(config.startingEnergy == 2)
        try config.validate()
    }

    @Test func validateRejectsNegativeStartingHealth() {
        var config = PlayerConfig.fallback
        config.startingHealth = -1
        #expect(throws: PlayerConfigError.invalid("starting_health must be >= 0")) {
            try config.validate()
        }
    }

    @Test func newWorldUsesStartingHudCounts() throws {
        let seed = WorldSeedConfig(
            version: 1,
            seed: 7,
            world: .init(width: 30, height: 30, stories: 1),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: 4,
                corridorWidth: 2,
                room: .init(
                    minRoomSize: 4,
                    maxRoomSize: 8,
                    pitChance: 0,
                    wallDestructibleChance: 0,
                    doorCount: 0
                )
            ),
            extensions: nil
        )
        let player = PlayerConfig(letter: "P", startingHealth: 4, startingEnergy: 1)
        let world = try ProceduralGenerator().generate(from: seed, playerConfig: player)
        #expect(world.healthCount == 4)
        #expect(world.energyCount == 1)
    }
}
