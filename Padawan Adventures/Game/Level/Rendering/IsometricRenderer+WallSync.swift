import SpriteKit

extension IsometricRenderer {
    /// Reuses wall / gate block nodes when kind, destructible flag, and faces are unchanged.
    /// Gates are parented under `occlusionLayer` with entities so pickup/player/enemy
    /// z adjustments can win or lose against the gate sprite as siblings.
    func syncWallNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()
        // Culled gates draw nothing, so they must not reorder entities either.
        gateOccluders = PlaceholderFactory.gateOccluders(in: world, story: story).filter {
            showsWall(at: $0.cell) || showsWall(at: $0.partner)
        }

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                guard showsWall(at: coord) else { continue }
                guard let identity = PlaceholderFactory.wallIdentity(
                    for: tile,
                    at: coord,
                    in: world,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                ) else {
                    continue
                }
                liveCoords.insert(coord)

                let sortCoord = PlaceholderFactory.wallSortCoord(for: tile, at: coord, in: world) ?? coord
                let screen = PlaceholderFactory.wallScreenPosition(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                ) ?? IsometricMath.gridToScreen(coord, config: config)
                let parentLayer = occlusionParent(for: tile)

                if let existing = wallNodes[coord], wallIdentities[coord] == identity {
                    if existing.parent !== parentLayer {
                        existing.removeFromParent()
                        parentLayer.addChild(existing)
                    }
                    existing.position = screen
                    existing.zPosition = IsometricMath.wallSortValue(for: sortCoord, config: config)
                    continue
                }

                wallNodes[coord]?.removeFromParent()
                let node = PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    floorTileSetLibrary: floorTileSetLibrary,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                )
                node.zPosition = IsometricMath.wallSortValue(for: sortCoord, config: config)
                applyRevealAlpha(to: node, at: coord)
                parentLayer.addChild(node)
                wallNodes[coord] = node
                wallIdentities[coord] = identity
            }
        }

        for coord in wallNodes.keys where !liveCoords.contains(coord) {
            wallNodes[coord]?.removeFromParent()
            wallNodes[coord] = nil
            wallIdentities[coord] = nil
        }
    }

    /// Gates share the entity layer; ordinary walls stay on `wallLayer`.
    func occlusionParent(for tile: Tile) -> SKNode {
        if case .gate = tile.kind { return occlusionLayer }
        return wallLayer
    }
}
