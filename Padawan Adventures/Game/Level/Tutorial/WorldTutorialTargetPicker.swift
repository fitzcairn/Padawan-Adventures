import Foundation

/// Picks a safe floor tile for the level-1 world tutorial's first tap demonstration.
nonisolated enum WorldTutorialTargetPicker {
    /// Preferred Chebyshev distance between the player and the demo target.
    static let preferredDistance = 3
    /// Collect candidates out to this Chebyshev distance (inclusive).
    private static let maxSearchDistance = 4
    /// Reject tiles closer than this Chebyshev distance.
    private static let minDistance = 2

    /// Picks a safe tile for the tutorial's first tap: ordinary floor only, reachable
    /// without crossing pits, gates, walls, or occupied cells. Returns nil when nothing
    /// suitable exists.
    static func demoTarget(in world: GameWorld) -> GridCoord? {
        let spawn = world.spawn
        let occupied = occupiedNonPlayerCells(in: world)

        var queue = [spawn]
        var distances: [GridCoord: Int] = [spawn: 0]
        var head = 0
        var candidates: [GridCoord] = []

        while head < queue.count {
            let current = queue[head]
            head += 1
            let distance = distances[current] ?? 0
            if distance >= maxSearchDistance { continue }

            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard next.story == spawn.story,
                      world.isInBounds(next),
                      distances[next] == nil else { continue }
                // Explore only through safe floor so candidates beyond hazards are not
                // considered "nearby" when they cannot be reached safely.
                guard isSafeFloor(next, in: world, occupied: occupied) else { continue }
                distances[next] = distance + 1
                queue.append(next)

                let nextDistance = chebyshev(next, spawn)
                guard nextDistance >= minDistance,
                      nextDistance <= maxSearchDistance,
                      safePath(from: spawn, to: next, in: world) != nil else { continue }
                candidates.append(next)
            }
        }

        return candidates.min { lhs, rhs in
            let lhsDistance = chebyshev(lhs, spawn)
            let rhsDistance = chebyshev(rhs, spawn)
            let lhsDelta = abs(lhsDistance - preferredDistance)
            let rhsDelta = abs(rhsDistance - preferredDistance)
            if lhsDelta != rhsDelta { return lhsDelta < rhsDelta }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }
    }

    /// Path from `start` to `goal` that steps only on ordinary (non-pit) floor tiles
    /// and never through gates or cells occupied by enemies/pickups.
    /// Returns `nil` when no such path exists.
    static func safePath(from start: GridCoord, to goal: GridCoord, in world: GameWorld) -> [GridCoord]? {
        guard start != goal else { return [start] }
        let occupied = occupiedNonPlayerCells(in: world)
        guard isSafeFloor(goal, in: world, occupied: occupied) else { return nil }

        var open: [GridCoord] = [start]
        var cameFrom: [GridCoord: GridCoord] = [:]
        var gScore: [GridCoord: Int] = [start: 0]
        var closed: Set<GridCoord> = []

        while !open.isEmpty {
            open.sort {
                (gScore[$0] ?? Int.max) + chebyshev($0, goal)
                    < (gScore[$1] ?? Int.max) + chebyshev($1, goal)
            }
            let current = open.removeFirst()
            if current == goal {
                return reconstructPath(from: start, to: goal, cameFrom: cameFrom)
            }
            closed.insert(current)

            for neighbor in safeNeighbors(of: current, in: world, occupied: occupied) {
                if closed.contains(neighbor) { continue }
                let tentative = (gScore[current] ?? Int.max) + 1
                if tentative < (gScore[neighbor] ?? Int.max) {
                    cameFrom[neighbor] = current
                    gScore[neighbor] = tentative
                    if !open.contains(neighbor) {
                        open.append(neighbor)
                    }
                }
            }
        }
        return nil
    }

    /// Ordinary non-pit floor, not a gate/wall, and not occupied by a non-player entity.
    static func isSafeFloor(
        _ coord: GridCoord,
        in world: GameWorld,
        occupied: Set<GridCoord>? = nil
    ) -> Bool {
        let blocked = occupied ?? occupiedNonPlayerCells(in: world)
        guard world.isInBounds(coord),
              let tile = world.tile(at: coord),
              case .floor(let isPit) = tile.kind,
              !isPit,
              !blocked.contains(coord) else { return false }
        return true
    }

    // MARK: - Private

    private static func occupiedNonPlayerCells(in world: GameWorld) -> Set<GridCoord> {
        Set(world.entities.compactMap { entity in
            entity.isPlayer ? nil : entity.position
        })
    }

    private static func safeNeighbors(
        of coord: GridCoord,
        in world: GameWorld,
        occupied: Set<GridCoord>
    ) -> [GridCoord] {
        var result: [GridCoord] = []
        for (dx, dy) in GridCoord.directions8 {
            let next = coord.neighbor(dx: dx, dy: dy)
            guard isSafeFloor(next, in: world, occupied: occupied) else { continue }
            // No corner-cutting: both adjacent cardinals must also be safe floors.
            if dx != 0, dy != 0 {
                let sideA = coord.neighbor(dx: dx, dy: 0)
                let sideB = coord.neighbor(dx: 0, dy: dy)
                guard isSafeFloor(sideA, in: world, occupied: occupied),
                      isSafeFloor(sideB, in: world, occupied: occupied) else { continue }
            }
            result.append(next)
        }
        return result
    }

    private static func reconstructPath(
        from start: GridCoord,
        to goal: GridCoord,
        cameFrom: [GridCoord: GridCoord]
    ) -> [GridCoord] {
        var path = [goal]
        var current = goal
        while current != start {
            guard let previous = cameFrom[current] else { return [start] }
            path.append(previous)
            current = previous
        }
        return path.reversed()
    }

    private static func chebyshev(_ a: GridCoord, _ b: GridCoord) -> Int {
        max(abs(a.x - b.x), abs(a.y - b.y))
    }
}
