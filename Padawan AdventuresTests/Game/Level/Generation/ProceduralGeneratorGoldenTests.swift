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
        11: "ad1414d9055a2b1fdb7477ae1c412980293e03c4c6ff835bca2cf860d34312f0",
        42: "397dc360408ec3c316d38abeffa6cb5f6eaace016d30dd6cb1bcaf928413ab92",
        99: "b30b4a4b0f881dbb9cfb5339ea414613584013160004d7461bcfd6ae3ae91592",
        123: "48da1b29582fc9c8bccd781e3018c3652383517a78c12f48ea0ffa885ab5bc31",
        777: "1af409bcca2529522a4cb82af3165aac1919fc8d4bdbe33174570dfaa8c438e9",
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
