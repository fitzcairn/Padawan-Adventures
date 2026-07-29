import Foundation

/// Which cells of a story may be drawn, so rooms behind a still-closed gate stay dark.
///
/// Rooms are packed one wall tile apart and only ever join through a gate, so "beyond a
/// locked gate" is the same as "floor the player cannot reach without crossing a gate".
/// Opening a gate turns its cells into ordinary floor, which makes the room past it
/// reachable — no separate explored/revealed state has to be stored or persisted.
nonisolated enum RoomVisibility {
    struct Result: Equatable, Sendable {
        /// Floor cells of the rooms the player can currently reach.
        var floorCells: Set<GridCoord>
        /// `floorCells` plus the wall/gate cells touching them, so the gates sealing a
        /// reachable room stay visible while the room behind them does not.
        var renderableCells: Set<GridCoord>

        static let empty = Result(floorCells: [], renderableCells: [])
    }

    /// - Parameter origin: Usually the player's cell. Cells are reachable relative to it.
    static func compute(in world: GameWorld, story: Int, from origin: GridCoord?) -> Result {
        guard story >= 0, story < world.storyCount else { return .empty }
        guard let seed = origin?.onStory(story), world.isInBounds(seed) else { return .empty }

        var floorCells = floodFloor(in: world, from: seed)
        // A player mid-encounter stands on the gate cell itself; keep them lit.
        floorCells.insert(seed)

        var renderableCells = floorCells
        for cell in floorCells {
            for (dx, dy) in GridCoord.directions8 {
                let neighbor = cell.neighbor(dx: dx, dy: dy)
                guard world.isInBounds(neighbor) else { continue }
                guard !isFloor(world.tile(at: neighbor)) else { continue }
                renderableCells.insert(neighbor)
            }
        }
        return Result(floorCells: floorCells, renderableCells: renderableCells)
    }

    /// Floor cells 4-connected to `seed`. Closed gates and walls block, so the flood stops
    /// at every gate the player has not opened yet.
    private static func floodFloor(in world: GameWorld, from seed: GridCoord) -> Set<GridCoord> {
        var reached: Set<GridCoord> = []
        var queue: [GridCoord] = []
        var head = 0

        // A player standing on a gate cell (mid-encounter) has no floor under them, so
        // seed from the cells around them rather than going dark.
        if isFloor(world.tile(at: seed)) {
            reached.insert(seed)
            queue.append(seed)
        } else {
            for (dx, dy) in GridCoord.cardinals {
                let neighbor = seed.neighbor(dx: dx, dy: dy)
                guard world.isInBounds(neighbor), isFloor(world.tile(at: neighbor)) else { continue }
                guard reached.insert(neighbor).inserted else { continue }
                queue.append(neighbor)
            }
        }

        while head < queue.count {
            let current = queue[head]
            head += 1
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard world.isInBounds(next), isFloor(world.tile(at: next)) else { continue }
                guard reached.insert(next).inserted else { continue }
                queue.append(next)
            }
        }
        return reached
    }

    private static func isFloor(_ tile: Tile?) -> Bool {
        guard let tile else { return false }
        if case .floor = tile.kind { return true }
        return false
    }
}
