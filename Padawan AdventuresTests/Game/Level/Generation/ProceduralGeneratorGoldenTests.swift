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
        11: "73f3f2b54624ce3329aa3554e82bd006176675522a0442e51ad265f76b7c58f5",
        42: "ba72e8b18e93df7430f8242864442a925a998d96855638135c07cba4bb8176c7",
        99: "5811d92aa525752197b87fdd3a434bf53400ba1d2f0741dc83cadc1bd8661308",
        123: "ad1abd2395fe4abde85f496d70fd887fa3362940a0e0c0a418d0ae4fa7f31162",
        777: "528731d96f255705d87dbfe3f67949a870c424add8fd3f7766e0a9cc97e973f1",
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
