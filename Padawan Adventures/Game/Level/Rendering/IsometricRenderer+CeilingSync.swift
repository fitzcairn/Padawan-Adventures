import SpriteKit

extension IsometricRenderer {
    /// Reuses ceiling diamonds when a cell still needs a roof overlay.
    func syncCeilingNodes(world: GameWorld, story: Int) {
        var liveCoords = Set<GridCoord>()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: story)
                guard showsWall(at: coord) else { continue }
                guard let identity = PlaceholderFactory.ceilingIdentity(at: coord, in: world) else {
                    continue
                }
                liveCoords.insert(coord)

                if let existing = ceilingNodes[coord], ceilingIdentities[coord] == identity {
                    if existing.parent !== wallLayer {
                        existing.removeFromParent()
                        wallLayer.addChild(existing)
                    }
                    existing.position = IsometricMath.gridToScreen(coord, config: config)
                    existing.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                    continue
                }

                ceilingNodes[coord]?.removeFromParent()
                let ceiling = PlaceholderFactory.ceilingNode(config: config)
                ceiling.position = IsometricMath.gridToScreen(coord, config: config)
                ceiling.zPosition = IsometricMath.wallSortValue(for: coord, config: config)
                applyRevealAlpha(to: ceiling, at: coord)
                wallLayer.addChild(ceiling)
                ceilingNodes[coord] = ceiling
                ceilingIdentities[coord] = identity
            }
        }

        for coord in ceilingNodes.keys where !liveCoords.contains(coord) {
            ceilingNodes[coord]?.removeFromParent()
            ceilingNodes[coord] = nil
            ceilingIdentities[coord] = nil
        }
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
