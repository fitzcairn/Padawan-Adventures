import Foundation

/// Resolves a world-HUD satellite tap to the level treasure and the tiles it scans.
nonisolated enum SatelliteScanUse {
    static let itemID = "merchant-ware-satelite"
    static let radius = 5

    static func artifactCoord(in world: GameWorld) -> GridCoord? {
        world.entities.first { $0.pickupKind == .treasure }?.position
    }

    /// In-bounds cells on `origin.story` whose Chebyshev distance equals `distance`.
    static func ring(origin: GridCoord, distance: Int, in world: GameWorld) -> [GridCoord] {
        guard distance >= 0 else { return [] }
        if distance == 0 {
            return world.isInBounds(origin) ? [origin] : []
        }
        var cells: [GridCoord] = []
        for dx in -distance...distance {
            for dy in -distance...distance {
                guard max(abs(dx), abs(dy)) == distance else { continue }
                let coord = origin.neighbor(dx: dx, dy: dy)
                if world.isInBounds(coord) {
                    cells.append(coord)
                }
            }
        }
        return cells
    }

    /// Floor cells in a ring that a scan should permanently uncover.
    static func floorsToReveal(origin: GridCoord, distance: Int, in world: GameWorld) -> Set<GridCoord> {
        Set(ring(origin: origin, distance: distance, in: world).filter { coord in
            if case .floor = world.tile(at: coord)?.kind { return true }
            return false
        })
    }
}
