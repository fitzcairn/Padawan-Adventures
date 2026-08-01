import SpriteKit

extension IsometricRenderer {
    /// Reuses base floor sprite nodes when terrain identity is unchanged.
    func syncFloorNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                let tile = world.tiles[story][y][x]
                guard case .floor = tile.kind,
                      showsFloor(at: coord),
                      let identity = PlaceholderFactory.floorIdentity(for: tile) else {
                    continue
                }
                liveCoords.insert(coord)

                if let existing = floorNodes[coord], floorIdentities[coord] == identity {
                    if existing.parent !== floorLayer {
                        existing.removeFromParent()
                        floorLayer.addChild(existing)
                    }
                    existing.position = PlaceholderFactory.floorScreenPosition(
                        for: tile,
                        at: coord,
                        config: config
                    )
                    existing.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                    continue
                }

                floorNodes[coord]?.removeFromParent()
                let node = PlaceholderFactory.tileNode(
                    for: tile,
                    at: coord,
                    in: world,
                    config: config,
                    floorTileSetLibrary: floorTileSetLibrary
                )
                node.zPosition = IsometricMath.floorSortValue(for: coord, config: config)
                applyRevealAlpha(to: node, at: coord)
                floorLayer.addChild(node)
                floorNodes[coord] = node
                floorIdentities[coord] = identity
            }
        }

        for coord in floorNodes.keys where !liveCoords.contains(coord) {
            floorNodes[coord]?.removeFromParent()
            floorNodes[coord] = nil
            floorIdentities[coord] = nil
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
