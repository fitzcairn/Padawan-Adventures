import SpriteKit

extension IsometricRenderer {
    /// Identity-keyed tile node sync shared by floor, wall, and ceiling passes.
    func syncIdentityKeyedNodes(
        world: GameWorld,
        story: Int,
        nodes: inout [GridCoord: SKNode],
        identities: inout [GridCoord: String],
        identity: (GridCoord, Tile) -> String?,
        parent: (GridCoord, Tile) -> SKNode,
        sortCoord: (GridCoord, Tile) -> GridCoord,
        layout: (SKNode, GridCoord, Tile, GridCoord) -> Void,
        makeNode: (GridCoord, Tile) -> SKNode
    ) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                guard let tileIdentity = identity(coord, tile) else { continue }
                liveCoords.insert(coord)

                let sorted = sortCoord(coord, tile)
                let parentLayer = parent(coord, tile)

                if let existing = nodes[coord], identities[coord] == tileIdentity {
                    if existing.parent !== parentLayer {
                        existing.removeFromParent()
                        parentLayer.addChild(existing)
                    }
                    layout(existing, coord, tile, sorted)
                    continue
                }

                nodes[coord]?.removeFromParent()
                let node = makeNode(coord, tile)
                layout(node, coord, tile, sorted)
                applyRevealAlpha(to: node, at: coord)
                parentLayer.addChild(node)
                nodes[coord] = node
                identities[coord] = tileIdentity
            }
        }

        for coord in nodes.keys where !liveCoords.contains(coord) {
            nodes[coord]?.removeFromParent()
            nodes[coord] = nil
            identities[coord] = nil
        }
    }
}
