import CoreGraphics
import Foundation

nonisolated extension IsometricMath {
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
        scale: CGFloat = 1,
        config: IsometricConfig = IsometricConfig()
    ) -> GridCoord {
        return screenToGrid(
            worldPointFromView(point, focus: focus, viewCenter: viewCenter, scale: scale),
            story: story,
            config: config
        )
    }

    /// Converts a scene touch point to world space using viewport focus and world scale.
    static func worldPointFromView(
        _ point: CGPoint,
        focus: CGPoint,
        viewCenter: CGPoint,
        scale: CGFloat = 1
    ) -> CGPoint {
        let safeScale = max(scale, 0.0001)
        return CGPoint(
            x: focus.x + (point.x - viewCenter.x) / safeScale,
            y: focus.y + (point.y - viewCenter.y) / safeScale
        )
    }

    /// Axis-aligned bounds of the floor diamonds for a rectangular grid on `story`.
    static func mapScreenBounds(
        width: Int,
        height: Int,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> CGRect {
        guard width > 0, height > 0 else { return .zero }

        let corners = [
            GridCoord(x: 0, y: 0, story: story),
            GridCoord(x: width - 1, y: 0, story: story),
            GridCoord(x: 0, y: height - 1, story: story),
            GridCoord(x: width - 1, y: height - 1, story: story),
        ]

        var minX = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity

        for corner in corners {
            let origin = gridToScreen(corner, config: config)
            // Floor diamond extends ±tileWidth/2 in X and 0…-tileHeight in Y from origin.
            minX = min(minX, origin.x - config.tileWidth / 2)
            maxX = max(maxX, origin.x + config.tileWidth / 2)
            minY = min(minY, origin.y - config.tileHeight)
            maxY = max(maxY, origin.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Uniform scale that fits `mapBounds` inside `viewSize` with `margin` (0…1 of the short side).
    static func fitScale(
        mapBounds: CGRect,
        viewSize: CGSize,
        margin: CGFloat = 0.06
    ) -> CGFloat {
        guard mapBounds.width > 0, mapBounds.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return 1
        }
        let inset = max(0, min(margin, 0.4))
        let available = CGSize(
            width: viewSize.width * (1 - inset * 2),
            height: viewSize.height * (1 - inset * 2)
        )
        let scale = min(available.width / mapBounds.width, available.height / mapBounds.height)
        return min(scale, 1)
    }

    /// World-space center of a map bounds rect (for viewport focus).
    static func mapCenter(for mapBounds: CGRect) -> CGPoint {
        CGPoint(x: mapBounds.midX, y: mapBounds.midY)
    }

    /// Offset for a world root node that places `focus` at `viewCenter` under `scale`.
    static func worldRootOffset(
        focus: CGPoint,
        viewCenter: CGPoint,
        scale: CGFloat = 1
    ) -> CGPoint {
        CGPoint(
            x: viewCenter.x - focus.x * scale,
            y: viewCenter.y - focus.y * scale
        )
    }

    /// Panning: drag finger by `delta` (scene space) → new focus so the world tracks the finger.
    static func focusAfterPan(
        currentFocus: CGPoint,
        dragDelta: CGPoint,
        scale: CGFloat = 1
    ) -> CGPoint {
        let safeScale = max(scale, 0.0001)
        return CGPoint(
            x: currentFocus.x - dragDelta.x / safeScale,
            y: currentFocus.y - dragDelta.y / safeScale
        )
    }

    /// Smoothstep interpolation between two viewport foci. `progress` is 0…1.
    static func interpolatedFocus(from start: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
        let clamped = min(max(progress, 0), 1)
        let t = clamped * clamped * (3 - 2 * clamped)
        return CGPoint(
            x: start.x + (end.x - start.x) * t,
            y: start.y + (end.y - start.y) * t
        )
    }
}
