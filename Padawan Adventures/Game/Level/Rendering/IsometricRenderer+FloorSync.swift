import SpriteKit

extension IsometricRenderer {
    /// Reuses base floor sprite nodes when terrain identity is unchanged.
    func syncFloorNodes(world: GameWorld, story: Int) {
        syncIdentityKeyedNodes(
            world: world,
            story: story,
            nodes: &floorNodes,
            identities: &floorIdentities,
            identity: { coord, tile in
                if case .gate = tile.kind {
                    // A gate strip is a hole in the floor; pave it so shallow gate art
                    // cannot leave the void showing beside the doorway.
                    guard showsWall(at: coord) else { return nil }
                    return PlaceholderFactory.doorwayFloorIdentity(at: coord, in: world)
                }
                guard case .floor = tile.kind,
                      showsFloor(at: coord),
                      let tileIdentity = PlaceholderFactory.floorIdentity(for: tile) else {
                    return nil
                }
                return tileIdentity
            },
            parent: { _, _ in floorLayer },
            sortCoord: { coord, _ in coord },
            layout: { node, coord, tile, sort in
                node.position = PlaceholderFactory.floorScreenPosition(
                    for: tile,
                    at: coord,
                    config: config
                )
                node.zPosition = IsometricMath.floorSortValue(for: sort, config: config)
            },
            makeNode: { coord, tile in
                if case .gate = tile.kind {
                    return PlaceholderFactory.doorwayFloorNode(
                        at: coord,
                        in: world,
                        config: config,
                        floorTileSetLibrary: floorTileSetLibrary
                    )
                }
                return PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    floorTileSetLibrary: floorTileSetLibrary
                )
            }
        )
    }

    /// Detaches floor nodes so a later sync can spawn replacements to cross-fade against.
    func takeFloorNodes(at coords: [GridCoord]) -> [SKNode] {
        coords.compactMap { coord in
            floorIdentities[coord] = nil
            return floorNodes.removeValue(forKey: coord)
        }
    }

    func clearFloorNodes() {
        for node in floorNodes.values {
            node.removeFromParent()
        }
        floorNodes.removeAll()
        floorIdentities.removeAll()
    }
}
