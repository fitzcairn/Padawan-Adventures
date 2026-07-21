import Testing
@testable import Padawan_Adventures

struct LineOfSightTests {
    @Test func clearCorridorCanSee() {
        let world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        let from = GridCoord(x: 0, y: 1, story: 0)
        let to = GridCoord(x: 4, y: 1, story: 0)
        #expect(LineOfSight.canSee(from: from, to: to, in: world))
    }

    @Test func solidWallBlocksSight() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)),
            at: GridCoord(x: 2, y: 1, story: 0)
        )
        let from = GridCoord(x: 0, y: 1, story: 0)
        let to = GridCoord(x: 4, y: 1, story: 0)
        #expect(LineOfSight.canSee(from: from, to: to, in: world) == false)
    }

    @Test func doorDoesNotBlockSight() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        world.setTile(
            Tile(kind: .wall(destructible: false, hasDoor: true, hasLadder: false)),
            at: GridCoord(x: 2, y: 1, story: 0)
        )
        let from = GridCoord(x: 0, y: 1, story: 0)
        let to = GridCoord(x: 4, y: 1, story: 0)
        #expect(LineOfSight.canSee(from: from, to: to, in: world))
    }

    @Test func differentStoryCannotSee() {
        let world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let from = GridCoord(x: 1, y: 1, story: 0)
        let to = GridCoord(x: 1, y: 1, story: 1)
        #expect(LineOfSight.canSee(from: from, to: to, in: world) == false)
    }

    @Test func sameTileCanSee() {
        let world = TestWorldFactory.emptyFloor(width: 3, height: 3)
        let coord = GridCoord(x: 1, y: 1, story: 0)
        #expect(LineOfSight.canSee(from: coord, to: coord, in: world))
    }
}
