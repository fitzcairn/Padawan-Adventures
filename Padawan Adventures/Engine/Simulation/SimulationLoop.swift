import CoreGraphics
import Foundation

struct EntityDisplayPose: Sendable {
    var entityID: UUID
    var occupancy: GridCoord
    var screenPosition: CGPoint
}

struct SimulationTickResult: Sendable {
    var shouldPersist: Bool = false
    var cameraCoord: GridCoord?
    var playerDisplayCoord: GridCoord?
    var playerDisplayPoint: CGPoint?
    var enemyDisplayPoses: [EntityDisplayPose] = []
    var animationFrame: Int = 0
    var movementEvents: [MovementEvent] = []
    /// Enemy that shares the player's occupancy tile this tick, if any.
    var enemyContactID: UUID?
    /// Pickup that shares the player's occupancy tile this tick, if any.
    var pickupContactID: UUID?
    /// True when the player entered a pit this tick (fell or hazard).
    var didEnterPit: Bool = false
}

struct SimulationLoop: Sendable {
    let pathfinder: Pathfinder
    let isoConfig: IsometricConfig
    private var enemyAI: EnemyAISystem
    private var enemyStates: [UUID: EnemyAIState] = [:]
    private var enemyMovements: [UUID: MovementSystem] = [:]
    private var encounterActive: Bool = false

    init(
        pathfinder: Pathfinder = Pathfinder(),
        isoConfig: IsometricConfig = IsometricConfig(),
        enemyConfig: EnemyConfig = .fallback
    ) {
        self.pathfinder = pathfinder
        self.isoConfig = isoConfig
        self.enemyAI = EnemyAISystem(enemyConfig: enemyConfig, pathfinder: pathfinder)
    }

    mutating func setEncounterActive(_ active: Bool) {
        encounterActive = active
    }

    mutating func removeEnemy(id: UUID, from world: inout GameWorld) {
        world.removeEntity(id: id)
        enemyStates[id] = nil
        enemyMovements[id] = nil
        encounterActive = false
    }

    mutating func tick(
        world: inout GameWorld,
        movement: inout MovementSystem,
        pendingInput: inout PendingInput,
        tickCount: UInt64
    ) -> SimulationTickResult {
        var result = SimulationTickResult()

        if encounterActive {
            result.animationFrame = Int(tickCount % 4)
            let occupancy = world.playerPosition ?? world.spawn
            result.playerDisplayCoord = occupancy
            result.playerDisplayPoint = movement.interpolatedScreenPosition(in: world, config: isoConfig)
            result.cameraCoord = occupancy
            result.enemyDisplayPoses = enemyDisplayPoses(world: world)
            return result
        }

        runControls(world: &world, movement: &movement, pendingInput: &pendingInput)
        enemyAI.update(
            world: &world,
            states: &enemyStates,
            movements: &enemyMovements,
            deltaTime: SimulationClock.tickDuration
        )
        result = runPositions(world: &world, movement: &movement, priorResult: result)
        result.enemyDisplayPoses = enemyDisplayPoses(world: world)
        result.enemyContactID = world.enemyInContactWithPlayer()?.id
        if result.enemyContactID != nil {
            encounterActive = true
        } else {
            result.pickupContactID = world.pickupInContactWithPlayer()?.id
        }
        result.animationFrame = Int(tickCount % 4)

        return result
    }

    private mutating func runControls(
        world: inout GameWorld,
        movement: inout MovementSystem,
        pendingInput: inout PendingInput
    ) {
        guard let tap = pendingInput.consume(),
              let playerPosition = world.playerPosition,
              let snapped = world.nearestValidMovementGoal(from: tap) else {
            return
        }

        guard let path = pathfinder.findPath(from: playerPosition, to: snapped, in: world),
              path.count >= 2 else {
            return
        }

        movement.begin(path: path)
    }

    private mutating func runPositions(
        world: inout GameWorld,
        movement: inout MovementSystem,
        priorResult: SimulationTickResult
    ) -> SimulationTickResult {
        var result = priorResult
        let wasMoving = movement.isMoving

        let events = movement.update(deltaTime: SimulationClock.tickDuration, world: &world)
        result.movementEvents = events
        result.didEnterPit = events.contains { event in
            if case .pit(let resolution) = event {
                return resolution != .none
            }
            return false
        }

        for event in events {
            if case .reached(let coord) = event {
                result.cameraCoord = coord
            }
        }

        let occupancy = world.playerPosition ?? world.spawn
        result.playerDisplayCoord = occupancy
        result.playerDisplayPoint = movement.interpolatedScreenPosition(in: world, config: isoConfig)

        result.cameraCoord = result.cameraCoord ?? occupancy
        result.shouldPersist = wasMoving && !movement.isMoving

        return result
    }

    private func enemyDisplayPoses(world: GameWorld) -> [EntityDisplayPose] {
        world.entities.compactMap { entity in
            guard entity.isEnemy else { return nil }
            let occupancy = entity.position
            let screen: CGPoint
            if let movement = enemyMovements[entity.id], movement.isMoving {
                screen = movement.interpolatedScreenPosition(
                    in: world,
                    entityID: entity.id,
                    config: isoConfig
                )
            } else {
                screen = IsometricMath.entityScreenPosition(occupancy, config: isoConfig)
            }
            return EntityDisplayPose(
                entityID: entity.id,
                occupancy: occupancy,
                screenPosition: screen
            )
        }
    }
}
