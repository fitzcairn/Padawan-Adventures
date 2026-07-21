import Testing
@testable import Padawan_Adventures

struct ProceduralGeneratorTests {
    @Test func sameSeedProducesIdenticalWorld() throws {
        let config = WorldSeedConfig(
            version: 1,
            seed: 99,
            world: .init(width: 16, height: 16, stories: 2),
            generation: .init(
                algorithm: "rooms_bsp",
                roomCount: 4,
                corridorWidth: 1,
                pitChance: 0.1,
                wallDestructibleChance: 0.3,
                rampCount: 1,
                ladderCount: 1,
                slideCount: 1,
                doorCount: 2
            ),
            player: .init(letter: "P", spawn: nil),
            extensions: nil
        )

        let first = try ProceduralGenerator().generate(from: config)
        let second = try ProceduralGenerator().generate(from: config)

        #expect(first.fingerprint() == second.fingerprint())
    }
}
