import CoreGraphics
import Foundation

struct IsometricConfig: Equatable, Sendable {
    /// Locked on-screen tile footprint (floor diamond width × height).
    var tileWidth: CGFloat = 40
    var tileHeight: CGFloat = 40
    var wallHeight: CGFloat = 40
    var storyHeight: CGFloat = 40
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

    /// Parent `zPosition` for the floor layer. Floors never share a band with sprites.
    static let floorBandBase: CGFloat = 0
    /// Parent `zPosition` for walls + entities. Must exceed any floor depth sort value.
    static let occlusionBandBase: CGFloat = 1_000_000

    /// Base isometric depth (far → near as `x + y` increases).
    /// Story is a minor key so the same cell's upper story draws above the lower,
    /// but an upper-story wall in the back does not bury a lower-story sprite in front.
    static func depthSortValue(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        CGFloat(coord.x + coord.y) * CGFloat(config.maxStories) + CGFloat(coord.story)
    }

    /// Floors sort among themselves only inside the floor band.
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

    /// Effective scene z for a floor tile (parent band + local sort).
    static func effectiveFloorZ(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        floorBandBase + floorSortValue(for: coord, config: config)
    }

    /// Effective scene z for an entity (parent band + local sort).
    static func effectiveEntityZ(for coord: GridCoord, config: IsometricConfig = IsometricConfig()) -> CGFloat {
        occlusionBandBase + entitySortValue(for: coord, config: config)
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

    /// Picks the frontmost drawn floor-surface tile under a tap on `story`.
    /// Walls, pits, doors, and entities are ignored; only non-pit floors, ramps, and slides count.
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
        ) { isDrawnFloorSurface($0) }
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

    private static func pickTile(
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
    private static func isDrawnFloorSurface(_ tile: Tile?) -> Bool {
        guard let tile else { return false }
        switch tile.kind {
        case .floor(let isPit):
            return !isPit
        case .ramp, .slide:
            return true
        case .wall:
            return false
        }
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
}
