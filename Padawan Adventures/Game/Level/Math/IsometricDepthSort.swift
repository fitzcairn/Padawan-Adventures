import CoreGraphics
import Foundation

nonisolated extension IsometricMath {
    /// Floor tiles live in a band strictly below walls/entities so floor art (including
    /// tall decor) never paints over sprites. Local depth still orders floors among themselves.
    static let floorBandBase: CGFloat = 0
    /// Walls and entities share this band and interleave by grid Y (front walls occlude sprites).
    /// Must stay above any floor local depth (`y * 10_000 * maxStories` on large maps).
    static let occlusionBandBase: CGFloat = 1_000_000_000

    /// Painter order: increasing grid **Y** draws on top (X, then story, break ties).
    /// Walls and entities share occlusion space so front walls can occlude sprites.
    /// Floors use the same local formula in a lower parent band.
    static func depthSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        depthSortValue(x: Double(coord.x), y: Double(coord.y), story: coord.story, config: config)
    }

    /// Continuous depth for fractional grid poses (used while entities interpolate between tiles).
    static func depthSortValue(
        x: Double,
        y: Double,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> CGFloat {
        let stories = max(config.maxStories, 1)
        // Stride large enough that any x/story at y+1 beats every tile at y.
        let xStride = CGFloat(stories)
        let yStride = CGFloat(10_000 * stories)
        return CGFloat(y) * yStride
            + CGFloat(x) * xStride
            + CGFloat(story)
    }

    static func floorSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        depthSortValue(for: coord, config: config)
    }

    static func wallSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        depthSortValue(for: coord, config: config)
    }

    /// Sprites sit slightly above floors/walls at the same cell (standing on the tile).
    static func entitySortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        entitySortValue(x: Double(coord.x), y: Double(coord.y), story: coord.story, config: config)
    }

    /// Entity sort keyed to continuous visual feet pose so mid-move sprites stay above
    /// the floors they are drawn over (occupancy snaps at progress 0.5; pose does not).
    static func entitySortValue(
        x: Double,
        y: Double,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> CGFloat {
        depthSortValue(x: x, y: y, story: story, config: config) + 0.5
    }

    /// Local painter order inside a small floor cluster (row-major, col tie-break).
    static func localTileSort(row: Int, col: Int) -> CGFloat {
        CGFloat(row) * 10 + CGFloat(col)
    }

    /// Effective scene z for a floor tile (parent band + local sort).
    static func effectiveFloorZ(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        floorBandBase + floorSortValue(for: coord, config: config)
    }

    /// Effective scene z for an entity (parent band + local sort).
    static func effectiveEntityZ(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        occlusionBandBase + entitySortValue(for: coord, config: config)
    }

    /// Effective scene z for an entity at a continuous grid pose.
    static func effectiveEntityZ(
        x: Double,
        y: Double,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> CGFloat {
        occlusionBandBase + entitySortValue(x: x, y: y, story: story, config: config)
    }

    /// True when a wall at `wallCoord` should draw on top of a sprite at `entityCoord`.
    static func wallOccludesEntity(
        wallCoord: GridCoord,
        entityCoord: GridCoord,
        config: IsometricConfig = IsometricConfig()
    ) -> Bool {
        wallSortValue(for: wallCoord, config: config) > entitySortValue(for: entityCoord, config: config)
    }
}
