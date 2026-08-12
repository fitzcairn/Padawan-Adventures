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
    /// Gate minigame kinds + pick weights for this level, in declaration order.
    var gateMinigames: [WeightedGateKind]
    /// Combat minigame kinds + pick weights, baked onto enemies at generation.
    var combatMinigames: [WeightedCombatKind]
    /// Pit minigame kinds + pick weights, baked onto each pit area at generation.
    var pitMinigames: [WeightedPitKind]

    nonisolated struct MapSize: Equatable, Sendable {
        var width: Int
        var height: Int
        /// Single-story worlds only; multi-story generation is not implemented.
        let stories: Int = 1

        nonisolated init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
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
        gateMinigames: [WeightedGateKind] = GateConfig.fallback.weightedMinigameKinds,
        combatMinigames: [WeightedCombatKind] = CombatConfig.fallback.weightedMinigameKinds,
        pitMinigames: [WeightedPitKind] = PitConfig.fallback.weightedMinigameKinds
    ) {
        self.seed = seed
        self.world = world
        self.generation = generation
        self.enemies = enemies
        self.pickups = pickups
        self.floorSet = floorSet
        self.decorProb = decorProb
        self.cohesion = cohesion
        self.gateMinigames = gateMinigames.isEmpty
            ? [WeightedGateKind(kind: .soundOutWord, weight: 1)]
            : gateMinigames
        self.combatMinigames = combatMinigames.isEmpty
            ? [WeightedCombatKind(kind: .slash, weight: 1)]
            : combatMinigames
        self.pitMinigames = pitMinigames.isEmpty
            ? [WeightedPitKind(kind: .soundOutWord, weight: 1)]
            : pitMinigames
    }

    static func compose(app: AppConfig, level: LevelConfig) -> WorldGenerationConfig {
        return WorldGenerationConfig(
            seed: app.seed,
            world: app.demoMode
                ? MapSize(width: DemoWorldBuilder.mapWidth, height: DemoWorldBuilder.mapHeight)
                : MapSize(
                    width: level.width,
                    height: level.height
                ),
            generation: level.generation,
            enemies: level.enemies,
            pickups: level.pickups,
            floorSet: level.floor.set,
            decorProb: level.floor.decorProb,
            cohesion: level.floor.cohesion,
            gateMinigames: level.gate.weightedMinigameKinds,
            combatMinigames: level.combat.weightedMinigameKinds,
            pitMinigames: level.pit.weightedMinigameKinds
        )
    }

    func resolvedSeed(at date: Date = Date()) -> UInt64 {
        if let seed { return seed }
        let millis = date.timeIntervalSince1970 * 1000
        let value = UInt64(millis.rounded(.down))
        return value == 0 ? 1 : value
    }

    func validate() throws {
        try GenerationParamsValidator.validate(
            width: world.width,
            height: world.height,
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
