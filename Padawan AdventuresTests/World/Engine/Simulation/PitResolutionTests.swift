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
        #expect(events.contains(.pit(.hazard)))
        #expect(world.playerPosition == pit)
        #expect(movement.isMoving == false)
    }
}
