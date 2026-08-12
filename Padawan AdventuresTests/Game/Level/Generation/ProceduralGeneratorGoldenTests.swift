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
        11: "73f8f457a496f63c974aab5b5cee4fbd13c62e50f8f18ce379f9144d6a8e228a",
        42: "2f33804f6beef1c6f997ecbc657d298dfc8276c826b8649a492bd163a6fc150e",
        99: "f7e51e9fe372c626b9fd34a92c3ef93a80e4e828e78e069be29b80290687c85f",
        123: "72aea505fc572621b8fb4ce16610fb43b9fe51c9bba20c46c629135801e67a60",
        777: "935e136fbd68f907b29a10af070f705c5cfdbb5986659592c904af74af0d6193",
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
