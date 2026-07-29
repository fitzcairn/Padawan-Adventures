import Foundation

enum EnemyAIMode: Equatable, Sendable {
    case idle
    case chasing
    case searching
}

struct EnemyAIState: Equatable, Sendable {
    var mode: EnemyAIMode = .idle
    var forgetElapsed: TimeInterval = 0
    var chaseGoal: GridCoord?
    /// True after the enemy first acquires line of sight; survives forget resets.
    var hasNoticedPlayer: Bool = false
}

struct EnemyAISystem: Sendable {
    let enemyConfig: EnemyConfig
    let pathfinder: Pathfinder

    init(enemyConfig: EnemyConfig = .fallback, pathfinder: Pathfinder = Pathfinder()) {
        self.enemyConfig = enemyConfig
        self.pathfinder = pathfinder
    }

    /// Updates chase / search AI. Returns enemy ids that newly noticed the player this tick.
    @discardableResult
    mutating func update(
        world: inout GameWorld,
        states: inout [UUID: EnemyAIState],
        movements: inout [UUID: MovementSystem],
        deltaTime: TimeInterval
    ) -> [UUID] {
        var noticed: [UUID] = []
        guard let playerPosition = world.playerPosition else { return noticed }

        let enemyIDs = Set(world.entities.filter(\.isEnemy).map(\.id))
        for id in states.keys where !enemyIDs.contains(id) {
            states[id] = nil
            movements[id] = nil
        }

        for entity in world.entities where entity.isEnemy {
            guard let typeID = entity.enemyTypeID,
                  let typeConfig = enemyConfig.type(named: typeID) else {
                continue
            }

            var state = states[entity.id] ?? EnemyAIState()
            var movement = movements[entity.id]
                ?? MovementSystem(tilesPerSecond: typeConfig.tilesPerSecond)
            movement.tilesPerSecond = typeConfig.tilesPerSecond

            // Prefer live position — the for-loop `entity` copy can be stale after movement commits.
            let currentPosition = world.entity(id: entity.id)?.position ?? entity.position
            let seesPlayer = LineOfSight.canSee(
                from: currentPosition,
                to: playerPosition,
                in: world
            )

            if seesPlayer {
                if !state.hasNoticedPlayer {
                    state.hasNoticedPlayer = true
                    noticed.append(entity.id)
                }
                state.mode = .chasing
                state.forgetElapsed = 0
                let liveEnemy = world.entity(id: entity.id) ?? entity
                repathIfNeeded(
                    enemy: liveEnemy,
                    goal: playerPosition,
                    state: &state,
                    movement: &movement,
                    world: world
                )
            } else if state.mode == .chasing || state.mode == .searching {
                // Finish the current tile step, then idle-search — avoids snapping to tile center.
                if state.mode == .chasing {
                    movement.finishCurrentSegmentAndStop()
                }
                state.mode = .searching
                state.forgetElapsed += deltaTime
                if state.forgetElapsed >= typeConfig.forgetSeconds {
                    let hadNoticed = state.hasNoticedPlayer
                    state = EnemyAIState()
                    state.hasNoticedPlayer = hadNoticed
                    if movement.isMoving {
                        movement.finishCurrentSegmentAndStop()
                    } else {
                        movement.reset()
                    }
                }
            }

            _ = movement.update(deltaTime: deltaTime, world: &world, entityID: entity.id)
            states[entity.id] = state
            movements[entity.id] = movement
        }
        return noticed
    }

    private func repathIfNeeded(
        enemy: GameEntity,
        goal: GridCoord,
        state: inout EnemyAIState,
        movement: inout MovementSystem,
        world: GameWorld
    ) {
        if state.chaseGoal == goal, movement.isMoving {
            return
        }
        state.chaseGoal = goal

        guard enemy.position != goal else {
            // Already on the goal tile — ease to a stop instead of hard-reset mid-pose.
            if movement.isMoving {
                movement.finishCurrentSegmentAndStop()
            }
            return
        }

        guard let path = pathfinder.findPath(from: enemy.position, to: goal, in: world),
              path.count >= 2 else {
            // Keep current motion; never snap by resetting on a failed repath.
            return
        }

        movement.retarget(path: path)
    }
}
