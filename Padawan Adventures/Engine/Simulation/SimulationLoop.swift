import CoreGraphics
import Foundation

struct SimulationTickResult: Sendable {
    var shouldPersist: Bool = false
    var cameraCoord: GridCoord?
    var playerDisplayCoord: GridCoord?
    var playerDisplayPoint: CGPoint?
    var animationFrame: Int = 0
    var movementEvents: [MovementEvent] = []
}

struct SimulationLoop: Sendable {
    let pathfinder: Pathfinder
    let isoConfig: IsometricConfig

    init(pathfinder: Pathfinder = Pathfinder(), isoConfig: IsometricConfig = IsometricConfig()) {
        self.pathfinder = pathfinder
        self.isoConfig = isoConfig
    }

    mutating func tick(
        world: inout GameWorld,
        movement: inout MovementSystem,
        pendingInput: inout PendingInput,
        tickCount: UInt64
    ) -> SimulationTickResult {
        var result = SimulationTickResult()

        runControls(world: &world, movement: &movement, pendingInput: &pendingInput)
        runAI(world: world)
        result = runPositions(world: &world, movement: &movement, priorResult: result)
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

        // Tapping a ramp/ladder on this story paths through it to the other story.
        let goal = world.movementGoalResolvingConnectors(from: playerPosition, goal: snapped)
        guard let path = pathfinder.findPath(from: playerPosition, to: goal, in: world),
              path.count >= 2 else {
            return
        }

        movement.begin(path: path)
    }

    private func runAI(world: GameWorld) {
        for entity in world.entities where !entity.isPlayer {
            _ = entity
        }
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
}
