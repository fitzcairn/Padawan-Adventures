import CoreGraphics
import Foundation

/// Visible sides of an isometric wall block relative to the tile diamond.
struct WallFaceSet: OptionSet, Sendable, Equatable {
    let rawValue: Int

    static let left = WallFaceSet(rawValue: 1 << 0)   // W–S edge (faces southwest)
    static let right = WallFaceSet(rawValue: 1 << 1)  // E–S edge (faces southeast)
    static let top = WallFaceSet(rawValue: 1 << 2)

    static let front: WallFaceSet = [.left, .right]
    static let all: WallFaceSet = [.left, .right, .top]
}

enum IsometricTileGeometry {
    /// Local diamond corners for a tile whose origin is the back (north) corner.
    struct Corners: Equatable, Sendable {
        var north: CGPoint
        var east: CGPoint
        var south: CGPoint
        var west: CGPoint
    }

    static func floorCorners(config: IsometricConfig) -> Corners {
        let halfW = config.tileWidth / 2
        let halfH = config.tileHeight / 2
        return Corners(
            north: CGPoint(x: 0, y: 0),
            east: CGPoint(x: halfW, y: -halfH),
            south: CGPoint(x: 0, y: -config.tileHeight),
            west: CGPoint(x: -halfW, y: -halfH)
        )
    }

    static func floorPath(config: IsometricConfig) -> CGPath {
        let c = floorCorners(config: config)
        let path = CGMutablePath()
        path.move(to: c.north)
        path.addLine(to: c.east)
        path.addLine(to: c.south)
        path.addLine(to: c.west)
        path.closeSubpath()
        return path
    }

    /// True when `worldPoint` lies inside the floor diamond for `coord`.
    /// Tile origin is the north corner (`gridToScreen`); diamond center is half a tile down.
    static func containsFloorPoint(
        _ worldPoint: CGPoint,
        at coord: GridCoord,
        config: IsometricConfig = IsometricConfig()
    ) -> Bool {
        let origin = IsometricMath.gridToScreen(coord, config: config)
        let localX = worldPoint.x - origin.x
        let localY = worldPoint.y - origin.y + config.tileHeight / 2
        let halfW = config.tileWidth / 2
        let halfH = config.tileHeight / 2
        guard halfW > 0, halfH > 0 else { return false }
        return abs(localX) / halfW + abs(localY) / halfH <= 1
    }

    /// Left wall face: parallelogram along the west–south edge, extruded upward.
    static func leftWallFacePath(config: IsometricConfig) -> CGPath {
        let c = floorCorners(config: config)
        let h = config.wallHeight
        let path = CGMutablePath()
        path.move(to: c.west)
        path.addLine(to: c.south)
        path.addLine(to: CGPoint(x: c.south.x, y: c.south.y + h))
        path.addLine(to: CGPoint(x: c.west.x, y: c.west.y + h))
        path.closeSubpath()
        return path
    }

    /// Right wall face: parallelogram along the east–south edge, extruded upward.
    static func rightWallFacePath(config: IsometricConfig) -> CGPath {
        let c = floorCorners(config: config)
        let h = config.wallHeight
        let path = CGMutablePath()
        path.move(to: c.east)
        path.addLine(to: c.south)
        path.addLine(to: CGPoint(x: c.south.x, y: c.south.y + h))
        path.addLine(to: CGPoint(x: c.east.x, y: c.east.y + h))
        path.closeSubpath()
        return path
    }

    /// Top cap of a wall block (raised floor diamond).
    static func topWallFacePath(config: IsometricConfig) -> CGPath {
        let c = floorCorners(config: config)
        let h = config.wallHeight
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.north.x, y: c.north.y + h))
        path.addLine(to: CGPoint(x: c.east.x, y: c.east.y + h))
        path.addLine(to: CGPoint(x: c.south.x, y: c.south.y + h))
        path.addLine(to: CGPoint(x: c.west.x, y: c.west.y + h))
        path.closeSubpath()
        return path
    }

    /// Which faces of a wall block are exposed given neighboring tiles.
    /// Left face sits on the +y side of the cell; right face on the +x side.
    static func visibleFaces(
        at coord: GridCoord,
        in world: GameWorld
    ) -> WallFaceSet {
        var faces: WallFaceSet = [.top]

        let rightNeighbor = coord.neighbor(dx: 1, dy: 0)
        if !isOpaqueWall(at: rightNeighbor, in: world) {
            faces.insert(.right)
        }

        let leftNeighbor = coord.neighbor(dx: 0, dy: 1)
        if !isOpaqueWall(at: leftNeighbor, in: world) {
            faces.insert(.left)
        }

        return faces
    }

    static func isOpaqueWall(at coord: GridCoord, in world: GameWorld) -> Bool {
        guard let tile = world.tile(at: coord) else { return false }
        return isOpaqueOccluder(tile)
    }

    /// Walls and gates draw solid blocks that can hide sprites behind them.
    static func isOpaqueOccluder(_ tile: Tile) -> Bool {
        switch tile.kind {
        case .wall, .gate:
            return true
        case .floor:
            return false
        }
    }

    /// East / south / southeast neighbors sit in front in isometric depth and can cover a sprite.
    static let frontOcclusionOffsets: [(Int, Int)] = [(1, 0), (0, 1), (1, 1)]

    /// True when a front-adjacent wall/gate would draw over a sprite standing on `coord`.
    static func hasFrontWallOccluder(at coord: GridCoord, in story: [[Tile]]) -> Bool {
        for (dx, dy) in frontOcclusionOffsets {
            let neighbor = coord.neighbor(dx: dx, dy: dy)
            guard neighbor.y >= 0, neighbor.y < story.count else { continue }
            guard neighbor.x >= 0, neighbor.x < story[neighbor.y].count else { continue }
            if isOpaqueOccluder(story[neighbor.y][neighbor.x]) { return true }
        }
        return false
    }

    /// True when any of the 8 neighbors is a wall/gate (pickup must sit ≥1 tile from walls).
    static func isAdjacentToOpaqueOccluder(at coord: GridCoord, in story: [[Tile]]) -> Bool {
        for (dx, dy) in GridCoord.directions8 {
            let neighbor = coord.neighbor(dx: dx, dy: dy)
            guard neighbor.y >= 0, neighbor.y < story.count else { continue }
            guard neighbor.x >= 0, neighbor.x < story[neighbor.y].count else { continue }
            if isOpaqueOccluder(story[neighbor.y][neighbor.x]) { return true }
        }
        return false
    }

    /// Floor cell suitable for pickups: non-pit floor, clear of adjacent walls/gates.
    static func isPickupVisibleFloor(at coord: GridCoord, in world: GameWorld) -> Bool {
        guard let tile = world.tile(at: coord) else { return false }
        guard case .floor(let isPit) = tile.kind, !isPit else { return false }
        guard coord.story >= 0, coord.story < world.tiles.count else { return false }
        return !isAdjacentToOpaqueOccluder(at: coord, in: world.tiles[coord.story])
    }

    /// True when the tile draws as a floor diamond (including pits).
    static func isDrawnFloorSurface(_ tile: Tile?) -> Bool {
        guard let tile else { return false }
        if case .floor = tile.kind { return true }
        return false
    }

    /// Opaque walls/gates that border walkable space get a full wall block (including top).
    static func shouldRenderWall(at coord: GridCoord, in world: GameWorld) -> Bool {
        guard isOpaqueWall(at: coord, in: world) else { return false }
        for (dx, dy) in GridCoord.cardinals {
            let neighbor = coord.neighbor(dx: dx, dy: dy)
            guard world.isInBounds(neighbor) else { continue }
            if isDrawnFloorSurface(world.tile(at: neighbor)) { return true }
            // Soft blockers also count as bordering "space" for mutual face culling.
            if world.isEnterable(at: neighbor) { return true }
        }
        return false
    }

    /// Gray CEILING diamond at wall-top height for gaps between walls / unrendered wall mass.
    static func needsCeiling(at coord: GridCoord, in world: GameWorld) -> Bool {
        guard world.isInBounds(coord) else { return false }
        guard !isDrawnFloorSurface(world.tile(at: coord)) else { return false }

        // Visible wall blocks already draw their own top face.
        if shouldRenderWall(at: coord, in: world) { return false }

        // Unrendered interior opaque wall mass — fill continuous roof.
        if isOpaqueWall(at: coord, in: world) { return true }

        // Gap between opposite opaque walls (e.g. pit corridor through wall mass).
        let north = isOpaqueWall(at: coord.neighbor(dx: 0, dy: -1), in: world)
        let south = isOpaqueWall(at: coord.neighbor(dx: 0, dy: 1), in: world)
        let east = isOpaqueWall(at: coord.neighbor(dx: 1, dy: 0), in: world)
        let west = isOpaqueWall(at: coord.neighbor(dx: -1, dy: 0), in: world)
        return (north && south) || (east && west)
    }
}
