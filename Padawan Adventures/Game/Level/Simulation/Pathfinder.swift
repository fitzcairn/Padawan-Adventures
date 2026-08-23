import Foundation

struct Pathfinder: Sendable {
    /// Finds a path to `goal`, or to the closest reachable cell if `goal` is unreachable.
    /// Returns `nil` only when `goal` is not a valid movement goal.
    func findPath(
        from start: GridCoord,
        to goal: GridCoord,
        in world: GameWorld,
        blocked: Set<GridCoord> = []
    ) -> [GridCoord]? {
        guard world.isValidMovementGoal(at: goal) else { return nil }
        guard start != goal else { return [start] }

        var open: [GridCoord] = [start]
        var cameFrom: [GridCoord: GridCoord] = [:]
        var gScore: [GridCoord: Int] = [start: 0]
        var closed: Set<GridCoord> = []

        while !open.isEmpty {
            open.sort { (gScore[$0] ?? Int.max) + heuristic($0, goal) < (gScore[$1] ?? Int.max) + heuristic($1, goal) }
            let current = open.removeFirst()

            if current == goal {
                return reconstructPath(from: start, to: goal, cameFrom: cameFrom)
            }

            closed.insert(current)

            for neighbor in neighbors(of: current, in: world, blocked: blocked) {
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

        let closest = closestReachable(to: goal, gScore: gScore)
        return reconstructPath(from: start, to: closest, cameFrom: cameFrom)
    }

    func neighbors(
        of coord: GridCoord,
        in world: GameWorld,
        blocked: Set<GridCoord> = []
    ) -> [GridCoord] {
        var result: [GridCoord] = []

        for (dx, dy) in GridCoord.directions8 {
            let next = coord.neighbor(dx: dx, dy: dy)
            guard world.isInBounds(next), world.isWalkable(at: next) else { continue }
            if blocked.contains(next) { continue }

            // No corner-cutting: both adjacent cardinals must be enterable.
            if dx != 0, dy != 0 {
                let sideA = coord.neighbor(dx: dx, dy: 0)
                let sideB = coord.neighbor(dx: 0, dy: dy)
                guard world.isEnterable(at: sideA), world.isEnterable(at: sideB) else { continue }
            }

            result.append(next)
        }

        return result
    }

    private func heuristic(_ a: GridCoord, _ b: GridCoord) -> Int {
        max(abs(a.x - b.x), abs(a.y - b.y)) + abs(a.story - b.story)
    }

    private func closestReachable(to goal: GridCoord, gScore: [GridCoord: Int]) -> GridCoord {
        gScore.keys.min { lhs, rhs in
            let lh = heuristic(lhs, goal)
            let rh = heuristic(rhs, goal)
            if lh != rh { return lh < rh }
            let lg = gScore[lhs] ?? Int.max
            let rg = gScore[rhs] ?? Int.max
            if lg != rg { return lg < rg }
            if lhs.story != rhs.story { return lhs.story < rhs.story }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        }!
    }

    private func reconstructPath(from start: GridCoord, to goal: GridCoord, cameFrom: [GridCoord: GridCoord]) -> [GridCoord] {
        var path = [goal]
        var current = goal
        while current != start {
            guard let previous = cameFrom[current] else { return [start] }
            path.append(previous)
            current = previous
        }
        return path.reversed()
    }
}
