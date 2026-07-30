import Foundation

nonisolated enum LineOfSight {
    /// True when `from` and `to` share a story and a grid ray between them hits no opaque wall.
    static func canSee(
        from: GridCoord,
        to: GridCoord,
        in world: GameWorld
    ) -> Bool {
        guard from.story == to.story else { return false }
        if from == to { return true }

        for cell in cellsOnLine(from: from, to: to) {
            if cell == from || cell == to { continue }
            if IsometricTileGeometry.isOpaqueWall(at: cell, in: world) {
                return false
            }
        }
        return true
    }

    /// Bresenham line cells from `from` to `to` (inclusive), ignoring story differences.
    static func cellsOnLine(from: GridCoord, to: GridCoord) -> [GridCoord] {
        var x0 = from.x
        var y0 = from.y
        let x1 = to.x
        let y1 = to.y
        let story = from.story

        let dx = abs(x1 - x0)
        let dy = abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1
        let sy = y0 < y1 ? 1 : -1
        var err = dx - dy

        var cells: [GridCoord] = []
        while true {
            cells.append(GridCoord(x: x0, y: y0, story: story))
            if x0 == x1 && y0 == y1 { break }
            let e2 = 2 * err
            if e2 > -dy {
                err -= dy
                x0 += sx
            }
            if e2 < dx {
                err += dx
                y0 += sy
            }
        }
        return cells
    }
}
