import CryptoKit
import Foundation
import Testing
@testable import Padawan_Adventures

struct ProceduralGeneratorGoldenTests {
    /// Copied from ProceduralGeneratorTests — `roomsDoorsConfig` is file-private there.
    private func roomsDoorsConfig(seed: UInt64 = 99, roomCount: Int = 6) -> WorldGenerationConfig {
        WorldGenerationConfig(
            seed: seed,
            world: .init(width: 30, height: 30, stories: 1),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: roomCount,
                corridorWidth: 2,
                room: .init(
                    minRoomSize: 4,
                    maxRoomSize: 10,
                    pitChance: 0.2,
                    partitionGateChance: 0.5
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
        11: "d8010fcb324465873cb6aca74c3763a66776e41a6d83f89efffa163994fd1c1d",
        42: "a177911a4748686572ce83117a50b50b98e069db2ed8e5cbc8f989b7ef8714ab",
        99: "7b9641d34e9ea4d6838f18009c62144f5cd5e0aa301eb788c1ea727c1569f784",
        123: "9a4761c03816f62b3977db31c89f2e93fc6dfacc14eba27b330163791eede944",
        777: "9435739ad4a8896d4eed3e9a5da4694042766f7b85be6784a7cc21e48ea9e634",
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
