import CoreGraphics
import Foundation

/// Composed app + level view used by `ProceduralGenerator` and save-compatibility checks.
nonisolated struct WorldGenerationConfig: Equatable, Sendable {
    var seed: UInt64?
    var world: MapSize
    var generation: LevelConfig.GenerationParams
    var enemies: LevelConfig.EnemiesSpawnConfig?
    var pickups: LevelConfig.PickupsSpawnConfig?
    var floorSet: String
    var decorProb: Double
    /// Distinct gate minigame kinds available for this level (first-seen order).
    var gateMinigameKinds: [GateMinigameKind]

    nonisolated struct MapSize: Equatable, Sendable {
        var width: Int
        var height: Int
        var stories: Int
    }

    nonisolated init(
        seed: UInt64? = nil,
        world: MapSize,
        generation: LevelConfig.GenerationParams,
        enemies: LevelConfig.EnemiesSpawnConfig? = nil,
        pickups: LevelConfig.PickupsSpawnConfig? = nil,
        floorSet: String = LevelConfig.fallbackFloor.set,
        decorProb: Double = LevelConfig.fallbackFloor.decorProb,
        gateMinigameKinds: [GateMinigameKind] = GateConfig.fallback.distinctMinigameKinds
    ) {
        self.seed = seed
        self.world = world
        self.generation = generation
        self.enemies = enemies
        self.pickups = pickups
        self.floorSet = floorSet
        self.decorProb = decorProb
        let kinds = gateMinigameKinds
        self.gateMinigameKinds = kinds.isEmpty ? [.spelling] : kinds
    }

    static func compose(app: AppConfig, level: LevelConfig) -> WorldGenerationConfig {
        let kinds = level.gate.distinctMinigameKinds
        return WorldGenerationConfig(
            seed: app.seed,
            world: MapSize(
                width: level.width,
                height: level.height,
                stories: app.world.stories
            ),
            generation: level.generation,
            enemies: level.enemies,
            pickups: level.pickups,
            floorSet: level.floor.set,
            decorProb: level.floor.decorProb,
            gateMinigameKinds: kinds.isEmpty ? [.spelling] : kinds
        )
    }

    func resolvedSeed(at date: Date = Date()) -> UInt64 {
        if let seed { return seed }
        let millis = date.timeIntervalSince1970 * 1000
        let value = UInt64(millis.rounded(.down))
        return value == 0 ? 1 : value
    }

    func validate() throws {
        guard generation.algorithm == "rooms_doors" else {
            throw WorldSeedError.unsupportedGenerationAlgorithm(generation.algorithm)
        }
        guard world.stories == 1 else {
            throw WorldSeedError.invalidStoryCount(world.stories)
        }
        guard world.width > 4, world.height > 4 else {
            throw WorldSeedError.worldTooSmall
        }
        guard !floorSet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorldSeedError.emptyFloorSet
        }
        guard decorProb >= 0, decorProb <= 1 else {
            throw WorldSeedError.invalidDecorProb(decorProb)
        }
        guard generation.corridorWidth >= 2 else {
            throw WorldSeedError.corridorTooNarrow(generation.corridorWidth)
        }
        guard generation.room.minRoomSize >= 2 else {
            throw WorldSeedError.roomTooNarrow(generation.room.minRoomSize)
        }
        guard generation.room.maxRoomSize >= generation.room.minRoomSize else {
            throw WorldSeedError.invalidRoomSizeRange
        }
        guard generation.room.pitChance >= 0, generation.room.pitChance <= 1 else {
            throw WorldSeedError.invalidRoomPitChance(generation.room.pitChance)
        }
        guard generation.room.pitMaxSize >= 1 else {
            throw WorldSeedError.invalidRoomPitSize(
                mean: generation.room.pitMeanSize,
                max: generation.room.pitMaxSize
            )
        }
        guard generation.room.pitMeanSize >= 1,
              generation.room.pitMeanSize <= Double(generation.room.pitMaxSize) else {
            throw WorldSeedError.invalidRoomPitSize(
                mean: generation.room.pitMeanSize,
                max: generation.room.pitMaxSize
            )
        }
        guard generation.room.partitionGateChance >= 0,
              generation.room.partitionGateChance <= 1 else {
            throw WorldSeedError.invalidRoomPartitionGateChance(generation.room.partitionGateChance)
        }
        if let enemies {
            guard !enemies.types.isEmpty, enemies.types.allSatisfy({ !$0.isEmpty }) else {
                throw WorldSeedError.invalidEnemyType
            }
            guard enemies.spawnChancePerRoom >= 0, enemies.spawnChancePerRoom <= 1 else {
                throw WorldSeedError.invalidEnemySpawnChance(enemies.spawnChancePerRoom)
            }
        }
        if let pickups {
            try Self.validatePickupChance(pickups.health?.spawnChancePerRoom, kind: .health)
            try Self.validatePickupChance(pickups.energy?.spawnChancePerRoom, kind: .energy)
        }
    }

    private static func validatePickupChance(_ chance: Double?, kind: PickupKind) throws {
        guard let chance else { return }
        guard chance >= 0, chance <= 1 else {
            throw WorldSeedError.invalidPickupSpawnChance(kind: kind, chance: chance)
        }
    }
}


/// Interactable kinds every valid map must include at least once.
nonisolated enum RequiredInteractable: String, Equatable, Sendable, CaseIterable {
    case gate
    case pit
    case enemy
}
