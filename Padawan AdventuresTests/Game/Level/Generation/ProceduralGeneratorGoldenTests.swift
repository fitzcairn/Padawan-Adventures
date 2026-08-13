import CryptoKit
import Foundation
import Testing
@testable import Padawan_Adventures

struct ProceduralGeneratorGoldenTests {
    /// Copied from ProceduralGeneratorTests — `roomsDoorsConfig` is file-private there.
    private func roomsDoorsConfig(seed: UInt64 = 99, roomCount: Int = 6) -> WorldGenerationConfig {
        WorldGenerationConfig(
            seed: seed,
            world: .init(width: 30, height: 30),
            generation: .init(
                roomCount: roomCount,
                room: .init(
                    minRoomSize: 4,
                    maxRoomSize: 10,
                    pitChance: 0.2,
                    gateProbability: 0.5
                )
            )
        )
    }

    /// Everything about a generated world that must not drift, in a stable order.
    /// Excludes `GameEntity.id` — a fresh UUID each run.
    private func signature(_ world: GameWorld) -> String {
        let entities = world.entities
            .map { e in
                [
                    String(e.letter),
                    "\(e.position.x),\(e.position.y),\(e.position.story)",
                    e.isPlayer ? "player" : "",
                    e.enemyTypeID ?? "",
                    e.pickupKind?.rawValue ?? "",
                ].joined(separator: ":")
            }
            .sorted()
            .joined(separator: "|")
        return world.fingerprint() + "\n##ENTITIES##\n" + entities
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 of `signature(world)` for each seed.
    /// Full unhashed signature for seed 42 lives beside this file as
    /// `ProceduralGeneratorGolden_seed42.txt` for offline diffing when a hash fails.
    private static let goldenHashes: [UInt64: String] = [
        11: "da983168045a398936d6be40279abb3e78ee86b908434dc797d865bf3e159cef",
        42: "ffd34bcaaedc9d0a6cd8be791345864d465a69f62a647d91ace9154bce0482c1",
        99: "a63e7e209cd94607587147a605f4690c14211a77abc00052b121780143628c29",
        123: "3e7c849578d3662b8433370586bae980ffeb623953efb9820aa16e7aaa165813",
        777: "a85cef8f3bec02a210b941b8824a9beb9daf4c86d54fb0ad7a836433fa2c0a19",
    ]

    private static let seeds: [UInt64] = [11, 42, 99, 123, 777]

    @Test func generatedWorldsMatchGolden() throws {
        for seed in Self.seeds {
            let config = roomsDoorsConfig(seed: seed, roomCount: 6)
            let world = try ProceduralGenerator().generate(from: config)
            let actual = signature(world)
            let actualHash = Self.sha256Hex(actual)
            if actualHash != Self.goldenHashes[seed] {
                let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
                    ?? NSHomeDirectory()
                let out = URL(fileURLWithPath: hostHome)
                    .appendingPathComponent("tmp/padawan_golden_drift_\(seed).txt")
                try? FileManager.default.createDirectory(
                    at: out.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? actual.write(to: out, atomically: true, encoding: .utf8)
            }
            #expect(
                actualHash == Self.goldenHashes[seed],
                "generation drifted at seed \(seed): got \(actualHash)"
            )
        }
    }
}
