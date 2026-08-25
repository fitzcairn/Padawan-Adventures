import Foundation

/// Resolves a world-HUD bridge tap to a unique nearby pit blob.
nonisolated enum BridgePitUse {
    static let itemID = "merchant-ware-bridge"
    static let maxDistance = 2

    struct Result: Equatable, Sendable {
        /// Any cell in the blob (`fillPit` floods from here).
        var seed: GridCoord
        var cells: [GridCoord]
    }

    static func resolve(in world: GameWorld) -> Result? {
        guard let player = world.playerPosition else { return nil }
        let inRange = pitGroups(in: world, story: player.story).filter { group in
            guard let distance = groupDistance(from: player, group: group) else { return false }
            return distance <= maxDistance
        }
        guard inRange.count == 1, let group = inRange.first else { return nil }
        return Result(seed: canonicalCell(in: group), cells: group)
    }

    /// Pit cells plus the floor neighbors `fillPit` will re-solve.
    static func fadeCoords(for result: Result, in world: GameWorld) -> [GridCoord] {
        var coords = Set(result.cells)
        for cell in result.cells {
            for (dx, dy) in GridCoord.cardinals {
                let neighbor = cell.neighbor(dx: dx, dy: dy)
                if case .floor = world.tile(at: neighbor)?.kind {
                    coords.insert(neighbor)
                }
            }
        }
        return Array(coords)
    }

    static func pitGroups(in world: GameWorld, story: Int) -> [[GridCoord]] {
        var visited: Set<GridCoord> = []
        var groups: [[GridCoord]] = []
        for y in 0..<world.height {
            for x in 0..<world.width {
                let start = GridCoord(x: x, y: y, story: story)
                guard !visited.contains(start), world.tile(at: start)?.isPit == true else { continue }
                groups.append(floodFill(from: start, in: world, visited: &visited))
            }
        }
        return groups
    }

    private static func floodFill(
        from start: GridCoord,
        in world: GameWorld,
        visited: inout Set<GridCoord>
    ) -> [GridCoord] {
        var queue = [start]
        var cells: [GridCoord] = []
        visited.insert(start)
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            cells.append(current)
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard world.isInBounds(next),
                      !visited.contains(next),
                      world.tile(at: next)?.isPit == true
                else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return cells
    }

    static func chebyshev(_ a: GridCoord, _ b: GridCoord) -> Int? {
        guard a.story == b.story else { return nil }
        return max(abs(a.x - b.x), abs(a.y - b.y))
    }

    private static func groupDistance(from player: GridCoord, group: [GridCoord]) -> Int? {
        group.compactMap { chebyshev(player, $0) }.min()
    }

    private static func canonicalCell(in group: [GridCoord]) -> GridCoord {
        group.min { lhs, rhs in
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x < rhs.x
        } ?? group[0]
    }
}
