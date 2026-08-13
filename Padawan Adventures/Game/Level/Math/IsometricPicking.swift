import CoreGraphics
import Foundation

nonisolated extension IsometricMath {
    /// Picks the frontmost drawn floor-surface tile under a tap on `story`.
    /// Walls are ignored; floors (including pits) and paved gate cells count.
    static func pickVisibleFloor(
        at viewPoint: CGPoint,
        focus: CGPoint,
        viewCenter: CGPoint,
        story: Int,
        in world: GameWorld,
        scale: CGFloat = 1,
        config: IsometricConfig = IsometricConfig()
    ) -> GridCoord? {
        pickTile(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: story,
            in: world,
            scale: scale,
            config: config
        ) { isTravelTargetSurface($0) }
    }

    /// Tap-to-move target: paved floor (including pits and gate cells) first, then any
    /// tile so a wall-only tap can still snap to a nearby movement goal.
    static func pickTravelTarget(
        at viewPoint: CGPoint,
        focus: CGPoint,
        viewCenter: CGPoint,
        story: Int,
        in world: GameWorld,
        scale: CGFloat = 1,
        config: IsometricConfig = IsometricConfig()
    ) -> GridCoord? {
        pickVisibleFloor(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: story,
            in: world,
            scale: scale,
            config: config
        ) ?? pickTile(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: story,
            in: world,
            scale: scale,
            config: config
        )
    }

    /// Picks the frontmost in-bounds tile under a tap on `story` (any kind).
    static func pickTile(
        at viewPoint: CGPoint,
        focus: CGPoint,
        viewCenter: CGPoint,
        story: Int,
        in world: GameWorld,
        scale: CGFloat = 1,
        config: IsometricConfig = IsometricConfig()
    ) -> GridCoord? {
        pickTile(
            at: viewPoint,
            focus: focus,
            viewCenter: viewCenter,
            story: story,
            in: world,
            scale: scale,
            config: config
        ) { _ in true }
    }

    static func pickTile(
        at viewPoint: CGPoint,
        focus: CGPoint,
        viewCenter: CGPoint,
        story: Int,
        in world: GameWorld,
        scale: CGFloat,
        config: IsometricConfig,
        predicate: (Tile?) -> Bool
    ) -> GridCoord? {
        guard story >= 0, story < world.storyCount else { return nil }

        let worldPoint = worldPointFromView(viewPoint, focus: focus, viewCenter: viewCenter, scale: scale)
        var best: GridCoord?
        var bestSort: CGFloat = -.infinity

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard predicate(world.tile(at: coord)) else { continue }
                guard IsometricTileGeometry.containsFloorPoint(worldPoint, at: coord, config: config) else {
                    continue
                }

                let sort = floorSortValue(for: coord, config: config)
                if sort > bestSort {
                    bestSort = sort
                    best = coord
                }
            }
        }

        return best
    }

    /// Matches tiles that `PlaceholderFactory` actually draws as floor diamonds.
    static func isDrawnFloorSurface(_ tile: Tile?) -> Bool {
        IsometricTileGeometry.isDrawnFloorSurface(tile)
    }

    /// Floor diamonds the player can tap to walk onto: ordinary floors, pits, and
    /// paved gate cells. Walls are excluded so a flanking wall cannot steal a
    /// doorway-floor tap.
    static func isTravelTargetSurface(_ tile: Tile?) -> Bool {
        guard let tile else { return false }
        switch tile.kind {
        case .floor, .gate:
            return true
        case .wall:
            return false
        }
    }
}
