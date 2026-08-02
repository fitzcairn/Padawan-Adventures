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
    var cohesion: Double
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
        cohesion: Double = LevelConfig.fallbackFloor.cohesion,
        gateMinigameKinds: [GateMinigameKind] = GateConfig.fallback.distinctMinigameKinds
    ) {
        self.seed = seed
        self.world = world
        self.generation = generation
        self.enemies = enemies
        self.pickups = pickups
        self.floorSet = floorSet
        self.decorProb = decorProb
        self.cohesion = cohesion
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
            cohesion: level.floor.cohesion,
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
        guard world.stories == 1 else {
            throw WorldSeedError.invalidStoryCount(world.stories)
        }
        try GenerationParamsValidator.validate(
            algorithm: generation.algorithm,
            width: world.width,
            height: world.height,
            corridorWidth: generation.corridorWidth,
            room: generation.room,
            floorSet: floorSet,
            decorProb: decorProb,
            cohesion: cohesion,
            enemies: enemies,
            pickups: pickups
        )
    }
}


/// Interactable kinds every valid map must include at least once.
nonisolated enum RequiredInteractable: String, Equatable, Sendable, CaseIterable {
    case gate
    case pit
    case enemy
}
