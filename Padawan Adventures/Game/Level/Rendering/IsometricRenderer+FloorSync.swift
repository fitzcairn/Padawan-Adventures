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
                PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    floorTileSetLibrary: floorTileSetLibrary
                )
            }
        )
    }

    func clearFloorNodes() {
        for node in floorNodes.values {
            node.removeFromParent()
        }
        floorNodes.removeAll()
        floorIdentities.removeAll()
    }
}
