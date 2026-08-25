import Foundation

/// Resolves a world-HUD jetpack tap to a unique nearby gate and a far-side landing tile.
nonisolated enum JetpackGateUse {
    static let itemID = "merchant-ware-jetpack"
    static let minDistance = 1
    static let maxDistance = 2

    struct Result: Equatable, Sendable {
        /// Any cell in the chosen group (`openGate` / `detachGateNode`).
        var gateCoord: GridCoord
        var landing: GridCoord
    }

    static func resolve(in world: GameWorld) -> Result? {
        guard let player = world.playerPosition else { return nil }
        let groups = gateGroups(in: world, story: player.story)

        var bestDistance = Int.max
        var closest: [[GridCoord]] = []
        for group in groups {
            guard let distance = groupDistance(from: player, group: group),
                  (minDistance...maxDistance).contains(distance)
            else { continue }
            if distance < bestDistance {
                bestDistance = distance
                closest = [group]
            } else if distance == bestDistance {
                closest.append(group)
            }
        }
        guard closest.count == 1, let group = closest.first else { return nil }
        guard let landing = landingTile(player: player, group: group, in: world) else { return nil }
        return Result(gateCoord: canonicalCell(in: group), landing: landing)
    }

    // MARK: - Groups

    /// Orthogonally contiguous same-kind gate blobs on `story` (same flood as `openGate`).
    static func gateGroups(in world: GameWorld, story: Int) -> [[GridCoord]] {
        var visited: Set<GridCoord> = []
        var groups: [[GridCoord]] = []
        for y in 0..<world.height {
            for x in 0..<world.width {
                let start = GridCoord(x: x, y: y, story: story)
                guard !visited.contains(start),
                      let kind = world.tile(at: start)?.gateMinigame
                else { continue }
                let group = floodFill(from: start, kind: kind, in: world, visited: &visited)
                groups.append(group)
            }
        }
        return groups
    }

    private static func floodFill(
        from start: GridCoord,
        kind: GateMinigameKind,
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
                guard !visited.contains(next),
                      world.tile(at: next)?.gateMinigame == kind
                else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return cells
    }

    // MARK: - Distance

    static func chebyshev(_ a: GridCoord, _ b: GridCoord) -> Int? {
        guard a.story == b.story else { return nil }
        return max(abs(a.x - b.x), abs(a.y - b.y))
    }

    private static func groupDistance(from player: GridCoord, group: [GridCoord]) -> Int? {
        group.compactMap { chebyshev(player, $0) }.min()
    }

    // MARK: - Landing

    private static func landingTile(
        player: GridCoord,
        group: [GridCoord],
        in world: GameWorld
    ) -> GridCoord? {
        guard let seed = group.first,
              let kind = world.tile(at: seed)?.gateMinigame
        else { return nil }

        if let strip = PlaceholderFactory.gateStrip(at: seed, minigame: kind, in: world) {
            return stripLanding(player: player, group: group, axis: strip.axis, in: world)
        }
        return singleCellLanding(player: player, cell: seed, in: world)
    }

    private static func stripLanding(
        player: GridCoord,
        group: [GridCoord],
        axis: GateSpriteSet.Axis,
        in world: GameWorld
    ) -> GridCoord? {
        let through = throughAxis(axis)
        var negative: Set<GridCoord> = []
        var positive: Set<GridCoord> = []
        for cell in group {
            let neg = cell.neighbor(dx: -through.dx, dy: -through.dy)
            let pos = cell.neighbor(dx: through.dx, dy: through.dy)
            if isNonPitFloor(neg, in: world) { negative.insert(neg) }
            if isNonPitFloor(pos, in: world) { positive.insert(pos) }
        }

        let negDist = minDistance(from: player, to: negative)
        let posDist = minDistance(from: player, to: positive)
        guard let negDist, let posDist, negDist != posDist else { return nil }

        let far = negDist > posDist ? negative : positive
        return closest(to: player, in: far)
    }

    private static func singleCellLanding(
        player: GridCoord,
        cell: GridCoord,
        in world: GameWorld
    ) -> GridCoord? {
        let neighbors = GridCoord.cardinals.compactMap { step -> GridCoord? in
            let next = cell.neighbor(dx: step.dx, dy: step.dy)
            return isNonPitFloor(next, in: world) ? next : nil
        }
        guard !neighbors.isEmpty else { return nil }
        let distances = neighbors.compactMap { coord -> (GridCoord, Int)? in
            guard let distance = chebyshev(player, coord) else { return nil }
            return (coord, distance)
        }
        guard let maxDistance = distances.map(\.1).max() else { return nil }
        let farthest = distances.filter { $0.1 == maxDistance }.map(\.0)
        guard farthest.count == 1 else { return nil }
        return farthest[0]
    }

    /// Through-axis step: rooms sit on ±Y for `alongX`, ±X for `alongY`.
    private static func throughAxis(_ axis: GateSpriteSet.Axis) -> (dx: Int, dy: Int) {
        switch axis {
        case .alongX: return (0, 1)
        case .alongY: return (1, 0)
        }
    }

    private static func isNonPitFloor(_ coord: GridCoord, in world: GameWorld) -> Bool {
        guard let tile = world.tile(at: coord) else { return false }
        if case .floor(let isPit) = tile.kind { return !isPit }
        return false
    }

    private static func minDistance(from player: GridCoord, to cells: Set<GridCoord>) -> Int? {
        cells.compactMap { chebyshev(player, $0) }.min()
    }

    private static func closest(to player: GridCoord, in cells: Set<GridCoord>) -> GridCoord? {
        cells.min { lhs, rhs in
            let ld = chebyshev(player, lhs) ?? Int.max
            let rd = chebyshev(player, rhs) ?? Int.max
            if ld != rd { return ld < rd }
            return compareCells(lhs, rhs)
        }
    }

    private static func canonicalCell(in group: [GridCoord]) -> GridCoord {
        group.min(by: compareCells) ?? group[0]
    }

    private static func compareCells(_ lhs: GridCoord, _ rhs: GridCoord) -> Bool {
        if lhs.story != rhs.story { return lhs.story < rhs.story }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.x < rhs.x
    }
}
