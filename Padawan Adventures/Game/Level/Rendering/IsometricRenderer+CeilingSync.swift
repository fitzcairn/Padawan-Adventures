import SpriteKit

extension IsometricRenderer {
    /// Reuses ceiling diamonds when a cell still needs a roof overlay.
    func syncCeilingNodes(world: GameWorld, story: Int) {
        syncIdentityKeyedNodes(
            world: world,
            story: story,
            nodes: &ceilingNodes,
            identities: &ceilingIdentities,
            identity: { coord, _ in
                guard showsWall(at: coord) else { return nil }
                return PlaceholderFactory.ceilingIdentity(at: coord, in: world)
            },
            parent: { _, _ in wallLayer },
            sortCoord: { coord, _ in coord },
            layout: { node, coord, _, sort in
                node.position = IsometricMath.gridToScreen(coord, config: config)
                node.zPosition = IsometricMath.wallSortValue(for: sort, config: config)
            },
            makeNode: { _, _ in
                PlaceholderFactory.ceilingNode(config: config)
            }
        )
    }

    func clearWallNodes() {
        for node in wallNodes.values {
            node.removeFromParent()
        }
        wallNodes.removeAll()
        wallIdentities.removeAll()
        gateOccluders = []
    }

    func clearCeilingNodes() {
        for node in ceilingNodes.values {
            node.removeFromParent()
        }
        ceilingNodes.removeAll()
        ceilingIdentities.removeAll()
    }
}
