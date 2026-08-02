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
    static func tile(
        tiles: inout [[Tile]],
        story: Int,
        set: FloorTileSet,
        options: Options,
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
        solve(
            tiles: &tiles,
            width: width,
            height: height,
            coords: floorCoords,
            set: set,
            options: options,
            rng: &rng
        )
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
