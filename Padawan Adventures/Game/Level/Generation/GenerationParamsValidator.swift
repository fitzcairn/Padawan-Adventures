import Foundation

/// Shared generation-parameter checks used by `LevelConfig` and `WorldGenerationConfig`.
nonisolated enum GenerationParamsValidator {
    static func validate(
        width: Int,
        height: Int,
        room: LevelConfig.RoomParams,
        floorSet: String,
        decorProb: Double,
        cohesion: Double = 0.75,
        enemies: LevelConfig.EnemiesSpawnConfig?,
        pickups: LevelConfig.PickupsSpawnConfig?
    ) throws {
        guard width > 4, height > 4 else {
            throw WorldSeedError.worldTooSmall
        }
        guard room.minRoomSize >= 2 else {
            throw WorldSeedError.roomTooNarrow(room.minRoomSize)
        }
        guard room.maxRoomSize >= room.minRoomSize else {
            throw WorldSeedError.invalidRoomSizeRange
        }
        guard room.pitChance >= 0, room.pitChance <= 1 else {
            throw WorldSeedError.invalidRoomPitChance(room.pitChance)
        }
        guard room.pitMaxSize >= 1 else {
            throw WorldSeedError.invalidRoomPitSize(mean: room.pitMeanSize, max: room.pitMaxSize)
        }
        guard room.pitMeanSize >= 1, room.pitMeanSize <= Double(room.pitMaxSize) else {
            throw WorldSeedError.invalidRoomPitSize(mean: room.pitMeanSize, max: room.pitMaxSize)
        }
        guard room.gateProbability >= 0, room.gateProbability <= 1 else {
            throw WorldSeedError.invalidGateProbability(room.gateProbability)
        }
        guard !floorSet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorldSeedError.emptyFloorSet
        }
        guard decorProb >= 0, decorProb <= 1 else {
            throw WorldSeedError.invalidDecorProb(decorProb)
        }
        guard cohesion >= 0, cohesion <= 1 else {
            throw WorldSeedError.invalidFloorCohesion(cohesion)
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
            try validatePickup(pickups.health, kind: .health)
            try validatePickup(pickups.energy, kind: .energy)
        }
    }

    static func validatePickup(_ config: LevelConfig.PickupChanceConfig?, kind: PickupKind) throws {
        guard let config else { return }
        try validatePickupChance(config.spawnChancePerRoom, kind: kind)
        try validatePickupCount(config.count, kind: kind)
    }

    static func validatePickupChance(_ chance: Double?, kind: PickupKind) throws {
        guard let chance else { return }
        guard chance >= 0, chance <= 1 else {
            throw WorldSeedError.invalidPickupSpawnChance(kind: kind, chance: chance)
        }
    }

    static func validatePickupCount(_ count: Int?, kind: PickupKind) throws {
        guard let count else { return }
        guard count >= 0 else {
            throw WorldSeedError.invalidPickupSpawnCount(kind: kind, count: count)
        }
    }
}
