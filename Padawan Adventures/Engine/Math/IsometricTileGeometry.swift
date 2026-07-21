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
        if case .wall(_, let hasDoor, _) = tile.kind {
            return !hasDoor
        }
        return false
    }

    /// True for the lexicographically smaller cell of a ramp/slide pair (draws the slope once).
    static func isCanonicalPairCell(_ coord: GridCoord, partner: GridCoord) -> Bool {
        if coord.x != partner.x { return coord.x < partner.x }
        return coord.y < partner.y
    }

    /// Sloped surface spanning a 2-cell ramp/slide pair along the partner axis.
    /// - Parameter rise: height added along the partner direction (`storyHeight` for ramps).
    /// - Parameter baseElevation: vertical offset of the low edge (`0` ramp, `-storyHeight` slide).
    static func connectorSlopePath(
        from coord: GridCoord,
        partner: GridCoord,
        config: IsometricConfig,
        rise: CGFloat,
        baseElevation: CGFloat = 0
    ) -> CGPath? {
        let dx = partner.x - coord.x
        let dy = partner.y - coord.y
        guard (dx == 1 && dy == 0) || (dx == 0 && dy == 1) else { return nil }

        let c = floorCorners(config: config)
        let halfW = config.tileWidth / 2
        let halfH = config.tileHeight / 2
        let ox = CGFloat(dx - dy) * halfW
        let oy = -CGFloat(dx + dy) * halfH
        let low = baseElevation
        let high = baseElevation + rise

        let path = CGMutablePath()
        if dx == 1 {
            // Rise toward +x partner.
            path.move(to: CGPoint(x: c.west.x, y: c.west.y + low))
            path.addLine(to: CGPoint(x: c.north.x, y: c.north.y + low))
            path.addLine(to: CGPoint(x: ox + c.north.x, y: oy + c.north.y + high))
            path.addLine(to: CGPoint(x: ox + c.east.x, y: oy + c.east.y + high))
            path.addLine(to: CGPoint(x: ox + c.south.x, y: oy + c.south.y + high))
            path.addLine(to: CGPoint(x: c.south.x, y: c.south.y + low))
        } else {
            // Rise toward +y partner.
            path.move(to: CGPoint(x: c.east.x, y: c.east.y + low))
            path.addLine(to: CGPoint(x: c.north.x, y: c.north.y + low))
            path.addLine(to: CGPoint(x: ox + c.north.x, y: oy + c.north.y + high))
            path.addLine(to: CGPoint(x: ox + c.west.x, y: oy + c.west.y + high))
            path.addLine(to: CGPoint(x: ox + c.south.x, y: oy + c.south.y + high))
            path.addLine(to: CGPoint(x: c.south.x, y: c.south.y + low))
        }
        path.closeSubpath()
        return path
    }
}
