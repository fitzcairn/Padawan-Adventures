import Foundation

/// Deterministic min-entropy floor tile assigner using the baked matches map.
nonisolated struct FloorTiler: Sendable {
    struct Options: Sendable {
        var decorProb: Double
        /// 0 = legacy per-cell variety, 1 = maximal patching.
        var cohesion: Double

        init(decorProb: Double = 0.06, cohesion: Double = 0.75) {
            self.decorProb = decorProb
            self.cohesion = cohesion
        }

        /// Off-family accent chance derived from cohesion.
        var accentProb: Double { 0.10 * (1.0 - cohesion) }
    }

    /// Salt so floor tiling does not perturb room/enemy/pickup RNG streams.
    static let seedSalt: UInt64 = 0xF1005E7

    /// Assigns `floorTileID` to every `.floor` tile on `story`.
    ///
    /// Supplying `rooms` makes each room draw from a single palette, which is
    /// what keeps a floor visually seamless. Rooms are separated by walls and
    /// joined by gates, so a palette change always lands in a doorway.
    static func tile(
        tiles: inout [[Tile]],
        story: Int,
        set: FloorTileSet,
        options: Options,
        rooms: [GeneratedRoom] = [],
        rng: inout SeededGenerator
    ) {
        let height = tiles.count
        guard height > 0 else { return }
        let width = tiles[0].count
        var coords: [GridCoord] = []
        for y in 0..<height {
            for x in 0..<width {
                if case .floor = tiles[y][x].kind {
                    coords.append(GridCoord(x: x, y: y, story: story))
                }
            }
        }
        solve(
            tiles: &tiles,
            width: width,
            height: height,
            coords: coords,
            set: set,
            options: options,
            rooms: rooms,
            rng: &rng
        )
    }

    /// Re-solves `coords` and their 4-neighbours (runtime mutations).
    static func retile(
        tiles: inout [[Tile]],
        story: Int,
        coords: [GridCoord],
        set: FloorTileSet,
        options: Options,
        rng: inout SeededGenerator
    ) {
        let height = tiles.count
        guard height > 0 else { return }
        let width = tiles[0].count
        var expanded = Set<GridCoord>()
        for coord in coords where coord.story == story {
            expanded.insert(coord)
            for side in FloorTileSet.Side.allCases {
                let d = FloorTileSet.delta(side)
                let n = GridCoord(x: coord.x + d.dx, y: coord.y + d.dy, story: story)
                if n.x >= 0, n.x < width, n.y >= 0, n.y < height {
                    expanded.insert(n)
                }
            }
        }
        let floorCoords = expanded
            .filter { coord in
                guard coord.y >= 0, coord.y < height, coord.x >= 0, coord.x < width else {
                    return false
                }
                if case .floor = tiles[coord.y][coord.x].kind { return true }
                return false
            }
            .sorted { a, b in
                if a.y != b.y { return a.y < b.y }
                return a.x < b.x
            }
        // No rooms at runtime; retiled cells inherit their palette from the
        // art already around them.
        solve(
            tiles: &tiles,
            width: width,
            height: height,
            coords: floorCoords,
            set: set,
            options: options,
            rooms: [],
            rng: &rng
        )
    }

    /// Units that each receive one palette: rooms when supplied, else
    /// 4-connected floor components.
    ///
    /// Cells belonging to no room — gate strips converted to floor by
    /// `GameWorld.openGate`, say — fall back to components so they are still
    /// grouped rather than left palette-less.
    static func groups(
        coords: [GridCoord],
        rooms: [GeneratedRoom],
        tiles: [[Tile]],
        width: Int,
        height: Int
    ) -> [[GridCoord]] {
        guard !rooms.isEmpty else {
            return regions(coords: coords, tiles: tiles, width: width, height: height)
        }
        let coordSet = Set(coords)
        var result: [[GridCoord]] = []
        var claimed = Set<GridCoord>()
        for room in rooms.sorted(by: { $0.id < $1.id }) {
            // Subtract `claimed` so a cell shared by two rooms lands in exactly
            // one group and cannot have its palette overwritten.
            let cells = room.cells
                .intersection(coordSet)
                .subtracting(claimed)
                .sorted { a, b in
                    if a.y != b.y { return a.y < b.y }
                    return a.x < b.x
                }
            guard !cells.isEmpty else { continue }
            result.append(cells)
            claimed.formUnion(cells)
        }
        let leftover = coords.filter { !claimed.contains($0) }
        if !leftover.isEmpty {
            result.append(
                contentsOf: regions(
                    coords: leftover,
                    tiles: tiles,
                    width: width,
                    height: height
                )
            )
        }
        return result
    }

    /// Group indices whose cells come within `radius` of one another. Rooms are
    /// separated by exactly one wall, so radius 2 finds true neighbours.
    static func adjacentGroups(
        _ groups: [[GridCoord]],
        radius: Int = 2
    ) -> [Int: Set<Int>] {
        var owner: [GridCoord: Int] = [:]
        for (index, group) in groups.enumerated() {
            for coord in group { owner[coord] = index }
        }
        var result: [Int: Set<Int>] = [:]
        for (index, group) in groups.enumerated() {
            for coord in group {
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let probe = GridCoord(
                            x: coord.x + dx,
                            y: coord.y + dy,
                            story: coord.story
                        )
                        if let other = owner[probe], other != index {
                            result[index, default: []].insert(other)
                        }
                    }
                }
            }
        }
        return result
    }

    /// 4-connected components of `.floor` cells among `coords`, in deterministic (y, x) order.
    static func regions(
        coords: [GridCoord],
        tiles: [[Tile]],
        width: Int,
        height: Int
    ) -> [[GridCoord]] {
        let coordSet = Set(coords)
        var remaining = coordSet
        var result: [[GridCoord]] = []
        let seeds = coords.sorted { a, b in
            if a.y != b.y { return a.y < b.y }
            return a.x < b.x
        }
        for seed in seeds {
            guard remaining.contains(seed) else { continue }
            var queue = [seed]
            var component: [GridCoord] = []
            remaining.remove(seed)
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                component.append(current)
                for side in FloorTileSet.Side.allCases {
                    let d = FloorTileSet.delta(side)
                    let next = GridCoord(
                        x: current.x + d.dx,
                        y: current.y + d.dy,
                        story: current.story
                    )
                    guard remaining.contains(next),
                          next.x >= 0, next.x < width,
                          next.y >= 0, next.y < height,
                          case .floor = tiles[next.y][next.x].kind else { continue }
                    remaining.remove(next)
                    queue.append(next)
                }
            }
            component.sort { a, b in
                if a.y != b.y { return a.y < b.y }
                return a.x < b.x
            }
            result.append(component)
        }
        return result
    }
}
