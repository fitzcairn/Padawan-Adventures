import CoreGraphics
import Foundation

struct IsometricConfig: Equatable, Sendable {
    var tileWidth: CGFloat = 64
    var tileHeight: CGFloat = 32
    var wallHeight: CGFloat = 48
    var storyHeight: CGFloat = 48
    /// Max stories used to interleave story into depth without burying lower stories
    /// under an entire upper-story layer.
    var maxStories: Int = 2
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

    /// Standing point for an entity on a tile (center of the floor diamond).
    static func entityScreenPosition(_ coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGPoint {
        let origin = gridToScreen(coord, config: config)
        return CGPoint(x: origin.x, y: origin.y - config.tileHeight * 0.5)
    }

    /// Base isometric depth (far → near as `x + y` increases).
    /// Story is a minor key so the same cell's upper story draws above the lower,
    /// but an upper-story wall in the back does not bury a lower-story sprite in front.
    static func depthSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        CGFloat(coord.x + coord.y) * CGFloat(config.maxStories) + CGFloat(coord.story)
    }

    /// Floors sort among themselves only; they never compete with sprites/walls.
    static func floorSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        depthSortValue(for: coord, config: config)
    }

    /// Walls in the occlusion band — in front of a sprite when depth is greater.
    static func wallSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        depthSortValue(for: coord, config: config)
    }

    /// Sprites sit slightly above walls at the same cell (e.g. doorways),
    /// but behind walls with greater isometric depth.
    static func entitySortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        depthSortValue(for: coord, config: config) + 0.5
    }

    /// True when a wall at `wallCoord` should draw on top of a sprite at `entityCoord`.
    static func wallOccludesEntity(
        wallCoord: GridCoord,
        entityCoord: GridCoord,
        config: IsometricConfig = IsometricConfig()
    ) -> Bool {
        wallSortValue(for: wallCoord, config: config) > entitySortValue(for: entityCoord, config: config)
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

    /// Scene-space position of a world point given a viewport focus (world space) and view center.
    static func viewPosition(
        worldPoint: CGPoint,
        focus: CGPoint,
        viewCenter: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: viewCenter.x + worldPoint.x - focus.x,
            y: viewCenter.y + worldPoint.y - focus.y
        )
    }

    /// View position for a grid cell with the given viewport focus.
    static func viewPosition(
        for coord: GridCoord,
        focus: CGPoint,
        viewCenter: CGPoint,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        viewPosition(
            worldPoint: gridToScreen(coord, config: config),
            focus: focus,
            viewCenter: viewCenter
        )
    }

    /// Converts a scene touch point to grid coordinates using viewport focus.
    static func gridFromView(
        _ point: CGPoint,
        focus: CGPoint,
        viewCenter: CGPoint,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> GridCoord {
        let worldLocal = CGPoint(
            x: point.x - viewCenter.x + focus.x,
            y: point.y - viewCenter.y + focus.y
        )
        return screenToGrid(worldLocal, story: story, config: config)
    }

    /// Offset for a world root node that places `focus` at `viewCenter`.
    static func worldRootOffset(
        focus: CGPoint,
        viewCenter: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: viewCenter.x - focus.x,
            y: viewCenter.y - focus.y
        )
    }

    /// Panning: drag finger by `delta` (scene space) → new focus so the world tracks the finger.
    static func focusAfterPan(currentFocus: CGPoint, dragDelta: CGPoint) -> CGPoint {
        CGPoint(
            x: currentFocus.x - dragDelta.x,
            y: currentFocus.y - dragDelta.y
        )
    }
}
