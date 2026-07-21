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
        switch tile.kind {
        case .wall, .gate:
            return true
        case .floor:
            return false
        }
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
