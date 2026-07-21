import CoreGraphics
import Foundation

struct IsometricConfig: Equatable, Sendable {
    var tileWidth: CGFloat = 64
    var tileHeight: CGFloat = 32
    var wallHeight: CGFloat = 48
    var storyHeight: CGFloat = 48
    var storyZBias: CGFloat = 10_000
}

enum IsometricMath {
    /// World-space position for a grid cell. Y increases upward in world space;
    /// larger `x + y` values map toward the bottom of the screen (front of the level).
    static func gridToScreen(_ coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGPoint {
        let screenX = CGFloat(coord.x - coord.y) * config.tileWidth / 2
        let screenY = -CGFloat(coord.x + coord.y) * config.tileHeight / 2
            + CGFloat(coord.story) * config.storyHeight
        return CGPoint(x: screenX, y: screenY)
    }

    /// View position with `anchor` centered at `viewCenter` (player-centered camera).
    static func viewPosition(
        for coord: GridCoord,
        anchor: GridCoord,
        viewCenter: CGPoint,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        let world = gridToScreen(coord, config: config)
        let anchorPoint = gridToScreen(anchor, config: config)
        return CGPoint(
            x: viewCenter.x + world.x - anchorPoint.x,
            y: viewCenter.y + world.y - anchorPoint.y
        )
    }

    static func depthSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        CGFloat(coord.x + coord.y) + CGFloat(coord.story) * config.storyZBias
    }

    static func screenToGrid(
        _ point: CGPoint,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> GridCoord {
        let adjustedY = point.y - CGFloat(story) * config.storyHeight
        let halfW = config.tileWidth / 2
        let halfH = config.tileHeight / 2

        // Inverse of screenX = (x-y)*halfW, screenY = -(x+y)*halfH
        let sum = -adjustedY / halfH
        let diff = point.x / halfW
        let gridX = (sum + diff) / 2
        let gridY = (sum - diff) / 2

        return GridCoord(
            x: Int(gridX.rounded()),
            y: Int(gridY.rounded()),
            story: story
        )
    }

    /// Converts a scene touch point to grid coordinates using player-centered view math.
    static func gridFromView(
        _ point: CGPoint,
        anchor: GridCoord,
        viewCenter: CGPoint,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> GridCoord {
        let anchorPoint = gridToScreen(anchor, config: config)
        let worldLocal = CGPoint(
            x: point.x - viewCenter.x + anchorPoint.x,
            y: point.y - viewCenter.y + anchorPoint.y
        )
        return screenToGrid(worldLocal, story: story, config: config)
    }

    /// Offset for a world root node that keeps `anchor` at `viewCenter`.
    static func worldRootOffset(
        anchor: GridCoord,
        viewCenter: CGPoint,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        let anchorPoint = gridToScreen(anchor, config: config)
        return CGPoint(
            x: viewCenter.x - anchorPoint.x,
            y: viewCenter.y - anchorPoint.y
        )
    }
}
