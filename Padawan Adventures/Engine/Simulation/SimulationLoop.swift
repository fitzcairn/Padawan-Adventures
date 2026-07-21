import Foundation

struct SimulationTickResult: Sendable {
    var shouldPersist: Bool = false
    var cameraCoord: GridCoord?
    var playerDisplayCoord: GridCoord?
    var animationFrame: Int = 0
    var movementEvents: [MovementEvent] = []
}

struct SimulationLoop: Sendable {
    let pathfinder: Pathfinder

    init(pathfinder: Pathfinder = Pathfinder()) {
        self.pathfinder = pathfinder
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
              world.isInBounds(tap),
              world.isEnterable(at: tap),
              let path = pathfinder.findPath(from: playerPosition, to: tap, in: world) else {
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

        if movement.isMoving {
            result.playerDisplayCoord = movement.interpolatedPosition(in: world)
        } else {
            result.playerDisplayCoord = world.playerPosition
        }

        result.cameraCoord = result.cameraCoord ?? world.playerPosition ?? world.spawn
        result.shouldPersist = wasMoving && !movement.isMoving

        return result
    }
}
