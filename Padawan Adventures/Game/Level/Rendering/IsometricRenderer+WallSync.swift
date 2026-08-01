import SpriteKit

extension IsometricRenderer {
    /// Reuses wall / gate block nodes when kind, destructible flag, and faces are unchanged.
    /// Gates are parented under `occlusionLayer` with entities so pickup/player/enemy
    /// z adjustments can win or lose against the gate sprite as siblings.
    func syncWallNodes(world: GameWorld, story: Int) {
        // Culled gates draw nothing, so they must not reorder entities either.
        gateOccluders = PlaceholderFactory.gateOccluders(in: world, story: story).filter {
            showsWall(at: $0.cell) || showsWall(at: $0.partner)
        }

        syncIdentityKeyedNodes(
            world: world,
            story: story,
            nodes: &wallNodes,
            identities: &wallIdentities,
            identity: { coord, tile in
                guard showsWall(at: coord) else { return nil }
                return PlaceholderFactory.wallIdentity(
                    for: tile,
                    at: coord,
                    in: world,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                )
            },
            parent: { _, tile in occlusionParent(for: tile) },
            sortCoord: { coord, tile in
                PlaceholderFactory.wallSortCoord(for: tile, at: coord, in: world) ?? coord
            },
            layout: { node, coord, tile, sort in
                node.position = PlaceholderFactory.wallScreenPosition(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                ) ?? IsometricMath.gridToScreen(coord, config: config)
                node.zPosition = IsometricMath.wallSortValue(for: sort, config: config)
            },
            makeNode: { coord, tile in
                PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    floorTileSetLibrary: floorTileSetLibrary,
                    gateSpriteSetLibrary: gateSpriteSetLibrary
                )
            }
        )
    }

    /// Gates share the entity layer; ordinary walls stay on `wallLayer`.
    func occlusionParent(for tile: Tile) -> SKNode {
        if case .gate = tile.kind { return occlusionLayer }
        return wallLayer
    }
}
