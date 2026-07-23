import Testing
@testable import Padawan_Adventures

struct PitResolutionTests {
    @Test func pitIsAlwaysHazard() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(pit)

        let resolution = world.resolvePit(at: pit)
        #expect(resolution == .hazard)
        #expect(world.playerPosition == pit)
    }

    @Test func enteringHazardPitStopsMovementAndStaysOnPit() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let start = GridCoord(x: 0, y: 1, story: 0)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(start)

        var movement = MovementSystem(tilesPerSecond: 1.0)
        movement.begin(path: [start, pit])

        let events = movement.update(deltaTime: 10, world: &world)
        #expect(events.contains(.pit(resolution: .hazard, approach: start)))
        #expect(world.playerPosition == pit)
        #expect(movement.isMoving == false)
    }

    @Test func nearestNonPitTileFindsAdjacentFloorAcrossPitBlob() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let pitA = GridCoord(x: 1, y: 1, story: 0)
        let pitB = GridCoord(x: 2, y: 1, story: 0)
        let rim = GridCoord(x: 3, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pitA)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pitB)

        // Cardinal BFS returns the first adjacent non-pit floor.
        #expect(world.nearestNonPitTile(from: pitA) == GridCoord(x: 1, y: 0, story: 0))
        #expect(world.nearestNonPitTile(from: pitB) == GridCoord(x: 2, y: 0, story: 0))
        #expect(world.nearestNonPitTile(from: rim) == rim)
    }

    @Test func relocatePlayerOffPitMovesToNearestNonPitFloor() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let pit = GridCoord(x: 1, y: 1, story: 0)
        world.setTile(Tile(kind: .floor(isPit: true)), at: pit)
        world.setPlayerPosition(pit)

        let relocated = world.relocatePlayerOffPit()
        #expect(relocated)
        let position = world.playerPosition
        #expect(position != nil)
        #expect(position != pit)
        if let position {
            #expect(world.tile(at: position)?.isPit != true)
            #expect(abs(position.x - pit.x) + abs(position.y - pit.y) == 1)
        }
    }

    @Test func relocatePlayerOffPitNoopsWhenNotOnPit() {
        var world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let floor = GridCoord(x: 1, y: 1, story: 0)
        world.setPlayerPosition(floor)

        let relocated = world.relocatePlayerOffPit()
        #expect(!relocated)
        #expect(world.playerPosition == floor)
    }
}
