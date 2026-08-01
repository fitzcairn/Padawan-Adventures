import SpriteKit
import UIKit

/// Shared, stateless arena helpers for pit minigames (pads, floor tiles, jump arc).
enum PitArenaLayout {
    private static let padCols = 2
    private static let padRows = 2

    /// Axis-aligned bounds of a 2×2 isometric floor diamond block.
    static func floorPadBounds(config: IsometricConfig) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        let corners = IsometricTileGeometry.floorCorners(config: config)
        for row in 0..<padRows {
            for col in 0..<padCols {
                let origin = IsometricMath.gridToScreen(
                    GridCoord(x: col, y: row, story: 0),
                    config: config
                )
                for point in [corners.north, corners.east, corners.south, corners.west] {
                    let world = CGPoint(x: origin.x + point.x, y: origin.y + point.y)
                    minX = min(minX, world.x)
                    maxX = max(maxX, world.x)
                    minY = min(minY, world.y)
                    maxY = max(maxY, world.y)
                }
            }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Quadratic-bezier jump position with smoothstep easing, `t` in 0...1.
    static func jumpPoint(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let clamped = min(max(t, 0), 1)
        let eased = clamped * clamped * (3 - 2 * clamped)
        let oneMinus = 1 - eased
        let x = oneMinus * oneMinus * start.x
            + 2 * oneMinus * eased * control.x
            + eased * eased * end.x
        let y = oneMinus * oneMinus * start.y
            + 2 * oneMinus * eased * control.y
            + eased * eased * end.y
        return CGPoint(x: x, y: y)
    }
}

/// One isometric floor tile at world scale, or nil when the set has no floor tiles.
func makeFloorTileNode(
    library: FloorTileSetLibrary,
    config: IsometricConfig,
    using rng: inout some RandomNumberGenerator
) -> SKNode? {
    guard let tileSet = library.tileSet else { return nil }
    let floorIDs = tileSet.floorTileIDs
    guard !floorIDs.isEmpty else { return nil }
    let tid = floorIDs[Int.random(in: 0..<floorIDs.count, using: &rng)]
    guard let texture = library.texture(tid),
          let frame = tileSet.frames[tid] else {
        return nil
    }
    return PlaceholderFactory.floorTileNode(
        tileID: tid,
        texture: texture,
        frame: frame,
        diamond: tileSet.meta.diamond,
        config: config
    )
}

/// The 2×2 isometric floor block used for the start / end pads, centered on its own midpoint.
func makeFloorPadCluster(
    library: FloorTileSetLibrary,
    config: IsometricConfig,
    using rng: inout some RandomNumberGenerator
) -> SKNode? {
    guard let tileSet = library.tileSet else { return nil }
    let floorIDs = tileSet.floorTileIDs
    guard !floorIDs.isEmpty else { return nil }

    let cluster = SKNode()
    let bounds = PitArenaLayout.floorPadBounds(config: config)

    for row in 0..<2 {
        for col in 0..<2 {
            let coord = GridCoord(x: col, y: row, story: 0)
            let origin = IsometricMath.gridToScreen(coord, config: config)
            let tid = floorIDs[Int.random(in: 0..<floorIDs.count, using: &rng)]
            guard let texture = library.texture(tid),
                  let frame = tileSet.frames[tid] else {
                continue
            }
            let tile = PlaceholderFactory.floorTileNode(
                tileID: tid,
                texture: texture,
                frame: frame,
                diamond: tileSet.meta.diamond,
                config: config
            )
            tile.position = origin
            // Local painter order only — world `floorSortValue` is ~10k×row and
            // buries the player when the SKView uses ignoresSiblingOrder / parent z sum.
            tile.zPosition = CGFloat(row) * 10 + CGFloat(col)
            cluster.addChild(tile)
        }
    }

    guard !cluster.children.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }

    // Center on the pad midpoint at 1:1 world scale (no squash — keeps perspective).
    cluster.position = CGPoint(x: -bounds.midX, y: -bounds.midY)
    return cluster
}
