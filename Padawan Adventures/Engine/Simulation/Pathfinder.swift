import Foundation

struct Pathfinder: Sendable {
    func findPath(from start: GridCoord, to goal: GridCoord, in world: GameWorld) -> [GridCoord]? {
        guard world.isEnterable(at: goal) else { return nil }
        guard start != goal else { return [start] }

        var open: [GridCoord] = [start]
        var cameFrom: [GridCoord: GridCoord] = [:]
        var gScore: [GridCoord: Int] = [start: 0]

        while !open.isEmpty {
            open.sort { (gScore[$0] ?? Int.max) + heuristic($0, goal) < (gScore[$1] ?? Int.max) + heuristic($1, goal) }
            let current = open.removeFirst()

            if current == goal {
                return reconstructPath(from: start, to: goal, cameFrom: cameFrom)
            }

            for neighbor in neighbors(of: current, in: world) {
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

    func neighbors(of coord: GridCoord, in world: GameWorld) -> [GridCoord] {
        var result: [GridCoord] = []

        for (dx, dy) in GridCoord.cardinals {
            let next = coord.neighbor(dx: dx, dy: dy)
            if world.isInBounds(next), world.isEnterable(at: next) {
                result.append(next)
            }
        }

        if let tile = world.tile(at: coord) {
            switch tile.kind {
            case .ramp(let partner, let otherStory):
                if world.isInBounds(partner), world.isEnterable(at: partner), partner != coord {
                    if !result.contains(partner) {
                        result.append(partner)
                    }
                }
                let vertical = coord.onStory(otherStory)
                if world.isInBounds(vertical), world.isEnterable(at: vertical) {
                    result.append(vertical)
                }

            case .slide(let partner, let lowerStory):
                if world.isInBounds(partner), world.isEnterable(at: partner), partner != coord {
                    if !result.contains(partner) {
                        result.append(partner)
                    }
                }
                if coord.story > lowerStory {
                    let lower = coord.onStory(lowerStory)
                    if world.isInBounds(lower), world.isEnterable(at: lower) {
                        result.append(lower)
                    }
                    let partnerLower = partner.onStory(lowerStory)
                    if world.isInBounds(partnerLower), world.isEnterable(at: partnerLower) {
                        result.append(partnerLower)
                    }
                }

            case .wall(_, _, let hasLadder) where hasLadder:
                for delta in [-1, 1] {
                    let vertical = coord.onStory(coord.story + delta)
                    if world.isInBounds(vertical), world.isEnterable(at: vertical) {
                        result.append(vertical)
                    }
                }

            default:
                break
            }
        }

        return result
    }

    private func heuristic(_ a: GridCoord, _ b: GridCoord) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y) + abs(a.story - b.story)
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
