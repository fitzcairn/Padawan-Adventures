import SpriteKit

extension IsometricRenderer {
    func updateVisibility(world: GameWorld, story: Int) {
        let previous = visibilityStory == story ? visibility.renderableCells : []
        visibility = RoomVisibility.compute(
            in: world,
            story: story,
            from: world.playerPosition ?? world.spawn
        )
        visibilityStory = story
        guard fadesNextReveal else { return }
        fadesNextReveal = false
        revealFadeCells = visibility.renderableCells.subtracting(previous)
        revealFadeEntityIDs.removeAll()
    }

    /// True when a cell is inside a reachable room (its floor art may draw).
    func showsFloor(at coord: GridCoord) -> Bool {
        visibility.floorCells.contains(coord)
    }

    /// True when a wall/gate cell borders a reachable room (a sealing gate stays visible).
    func showsWall(at coord: GridCoord) -> Bool {
        visibility.renderableCells.contains(coord)
    }

    /// Newly revealed art starts invisible so `playGateOpenAnimation` can fade it in.
    func applyRevealAlpha(to node: SKNode, at coord: GridCoord) {
        guard revealFadeCells.contains(coord) else { return }
        node.alpha = 0
    }
}
