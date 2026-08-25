import Testing
@testable import Padawan_Adventures

struct JetpackGateUseTests {
    @Test func noGateFails() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    @Test func distanceThreeFails() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 6, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    @Test func uniqueStripAtDistanceOneLandsOpposite() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 4, story: 0))

        let result = JetpackGateUse.resolve(in: world)
        #expect(result?.gateCoord == GridCoord(x: 3, y: 3, story: 0))
        #expect(result?.landing == GridCoord(x: 3, y: 2, story: 0))
    }

    @Test func uniqueStripAtDistanceTwoLandsOpposite() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 5, story: 0))

        let result = JetpackGateUse.resolve(in: world)
        #expect(result?.landing == GridCoord(x: 3, y: 2, story: 0))
    }

    @Test func diagonalNeighborCountsAsOne() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))

        let result = JetpackGateUse.resolve(in: world)
        #expect(result != nil)
        #expect(JetpackGateUse.chebyshev(GridCoord(x: 2, y: 2, story: 0), GridCoord(x: 3, y: 3, story: 0)) == 1)
        #expect(result?.landing == GridCoord(x: 3, y: 4, story: 0))
    }

    @Test func twoGroupsAtSameDistanceFail() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 2, y: 1, story: 0))
        placeAlongXStrip(in: &world, origin: GridCoord(x: 2, y: 5, story: 0))
        world.setPlayerPosition(GridCoord(x: 2, y: 3, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    @Test func closerOfTwoGroupsWins() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 2, y: 2, story: 0))
        placeAlongXStrip(in: &world, origin: GridCoord(x: 2, y: 5, story: 0))
        world.setPlayerPosition(GridCoord(x: 2, y: 3, story: 0))

        let result = JetpackGateUse.resolve(in: world)
        #expect(result?.gateCoord == GridCoord(x: 2, y: 2, story: 0))
        #expect(result?.landing == GridCoord(x: 2, y: 1, story: 0))
    }

    @Test func twoCellsOfOneStripAreOneGroup() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 4, y: 4, story: 0))

        let result = JetpackGateUse.resolve(in: world)
        #expect(result != nil)
        #expect(JetpackGateUse.gateGroups(in: world, story: 0).count == 1)
    }

    @Test func alongYStripLandsOnFarSideFloor() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongYStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 1, y: 3, story: 0))

        let result = JetpackGateUse.resolve(in: world)
        #expect(result?.landing == GridCoord(x: 4, y: 3, story: 0))
    }

    @Test func besideStripFails() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 5, y: 3, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    @Test func oppositeSidePitFails() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setTile(Tile(kind: .floor(isPit: true)), at: GridCoord(x: 3, y: 2, story: 0))
        world.setTile(Tile(kind: .floor(isPit: true)), at: GridCoord(x: 4, y: 2, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 4, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    @Test func oppositeSideWallFails() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 3, y: 2, story: 0))
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 4, y: 2, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 4, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    @Test func oppositeSideOutOfBoundsFails() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 3)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 1, y: 0, story: 0))
        world.setPlayerPosition(GridCoord(x: 1, y: 1, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    @Test func standingOnGateFails() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placeAlongXStrip(in: &world, origin: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 3, story: 0))
        #expect(JetpackGateUse.resolve(in: world) == nil)
    }

    private func placeAlongXStrip(in world: inout GameWorld, origin: GridCoord) {
        let partner = origin.neighbor(dx: 1, dy: 0)
        world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: origin)
        world.setTile(Tile(kind: .gate(minigame: .soundOutWord)), at: partner)
    }

    private func placeAlongYStrip(in world: inout GameWorld, origin: GridCoord) {
        let partner = origin.neighbor(dx: 0, dy: 1)
        world.setTile(Tile(kind: .gate(minigame: .graphemeMatch)), at: origin)
        world.setTile(Tile(kind: .gate(minigame: .graphemeMatch)), at: partner)
    }
}
