import CoreGraphics
import Foundation

extension IsometricMath {
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
        entityScreenPosition(x: Double(coord.x), y: Double(coord.y), story: coord.story, config: config)
    }

    /// Standing point for a continuous (fractional) grid pose.
    static func entityScreenPosition(
        x: Double,
        y: Double,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        let screenX = CGFloat(x - y) * config.tileWidth / 2
        let screenY = -CGFloat(x + y) * config.tileHeight / 2
            + CGFloat(story) * config.storyHeight
        return CGPoint(x: screenX, y: screenY - config.tileHeight * 0.5)
    }

    /// Inverse of `entityScreenPosition(x:y:story:)` — fractional grid without rounding.
    static func fractionalGridFromEntityScreen(
        _ point: CGPoint,
        story: Int,
        config: IsometricConfig = IsometricConfig()
    ) -> (x: Double, y: Double) {
        let halfW = config.tileWidth / 2
        let halfH = config.tileHeight / 2
        guard halfW > 0, halfH > 0 else { return (0, 0) }

        let adjustedY = point.y + config.tileHeight * 0.5 - CGFloat(story) * config.storyHeight
        let sum = -adjustedY / halfH
        let diff = point.x / halfW
        return (
            x: Double((sum + diff) / 2),
            y: Double((sum - diff) / 2)
        )
    }

    /// Shifts `focus` only when `player` leaves a ±`maxTiles` grid window around screen center.
    static func focusKeepingPlayerInDeadzone(
        focus: CGPoint,
        player: CGPoint,
        story: Int,
        maxTiles: Double = 2,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        let focusGrid = fractionalGridFromEntityScreen(focus, story: story, config: config)
        let playerGrid = fractionalGridFromEntityScreen(player, story: story, config: config)

        var focusX = focusGrid.x
        var focusY = focusGrid.y

        if playerGrid.x > focusX + maxTiles {
            focusX = playerGrid.x - maxTiles
        } else if playerGrid.x < focusX - maxTiles {
            focusX = playerGrid.x + maxTiles
        }

        if playerGrid.y > focusY + maxTiles {
            focusY = playerGrid.y - maxTiles
        } else if playerGrid.y < focusY - maxTiles {
            focusY = playerGrid.y + maxTiles
        }

        return entityScreenPosition(x: focusX, y: focusY, story: story, config: config)
    }
}
