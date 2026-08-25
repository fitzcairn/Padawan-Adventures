import Foundation
import CoreGraphics

/// Resolves a world-HUD vector tap to enemies currently on camera.
nonisolated enum VectorStrafeUse {
    static let itemID = "merchant-ware-vector"

    /// Enemies whose room is revealed and whose standing point is inside the camera.
    static func visibleEnemies(
        in world: GameWorld,
        shownFloorCells: Set<GridCoord>,
        focus: CGPoint,
        viewCenter: CGPoint,
        viewSize: CGSize,
        scale: CGFloat,
        config: IsometricConfig = IsometricConfig()
    ) -> [GameEntity] {
        world.entities.filter { entity in
            guard entity.isEnemy, shownFloorCells.contains(entity.position) else { return false }
            return IsometricMath.isOnScreen(
                worldPoint: IsometricMath.entityScreenPosition(entity.position, config: config),
                focus: focus,
                viewCenter: viewCenter,
                viewSize: viewSize,
                scale: scale
            )
        }
    }

    /// Screen-space unit vector along an isometric tile edge toward the southwest.
    static func isoSouthwestUnit(config: IsometricConfig, scale: CGFloat = 1) -> CGVector {
        let dx = -config.tileWidth * scale
        let dy = -config.tileHeight * scale
        let length = hypot(dx, dy)
        guard length > 0 else { return CGVector(dx: 0, dy: -1) }
        return CGVector(dx: dx / length, dy: dy / length)
    }

    /// Off-screen NE → off-screen SW, parallel to the isometric tile edges through `anchor`.
    static func flightPath(
        through anchor: CGPoint,
        viewSize: CGSize,
        config: IsometricConfig,
        scale: CGFloat,
        offscreenPadding: CGFloat
    ) -> (start: CGPoint, end: CGPoint) {
        let southwest = isoSouthwestUnit(config: config, scale: scale)
        let halfW = viewSize.width * 0.5 + offscreenPadding
        let halfH = viewSize.height * 0.5 + offscreenPadding
        let start = pointOffScreen(
            from: anchor,
            dx: -southwest.dx,
            dy: -southwest.dy,
            halfWidth: halfW,
            halfHeight: halfH
        )
        let end = pointOffScreen(
            from: anchor,
            dx: southwest.dx,
            dy: southwest.dy,
            halfWidth: halfW,
            halfHeight: halfH
        )
        return (start, end)
    }

    /// First point on the ray that sits outside the padded camera rectangle.
    static func pointOffScreen(
        from origin: CGPoint,
        dx: CGFloat,
        dy: CGFloat,
        halfWidth: CGFloat,
        halfHeight: CGFloat
    ) -> CGPoint {
        var travel = CGFloat.greatestFiniteMagnitude
        if dx != 0 {
            let edge = dx > 0 ? halfWidth : -halfWidth
            let t = (edge - origin.x) / dx
            if t > 0 { travel = min(travel, t) }
        }
        if dy != 0 {
            let edge = dy > 0 ? halfHeight : -halfHeight
            let t = (edge - origin.y) / dy
            if t > 0 { travel = min(travel, t) }
        }
        if !travel.isFinite || travel == .greatestFiniteMagnitude {
            travel = max(halfWidth, halfHeight)
        }
        return CGPoint(x: origin.x + dx * travel, y: origin.y + dy * travel)
    }

    /// How far along a NE→SW strafe the ship is when it should fire at `target` (0…1).
    static func fireProgress(from start: CGPoint, to end: CGPoint, target: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1 else { return 0.5 }
        let projected = ((target.x - start.x) * dx + (target.y - start.y) * dy) / lengthSquared
        return min(max(projected, 0.12), 0.88)
    }
}
