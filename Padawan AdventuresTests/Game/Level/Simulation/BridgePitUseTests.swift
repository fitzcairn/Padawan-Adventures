import Testing
@testable import Padawan_Adventures

struct BridgePitUseTests {
    @Test func noPitFails() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))
        #expect(BridgePitUse.resolve(in: world) == nil)
    }

    @Test func distanceThreeFails() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placePit(in: &world, at: GridCoord(x: 3, y: 3, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 6, story: 0))
        #expect(BridgePitUse.resolve(in: world) == nil)
    }

    @Test func uniquePitAtDistanceOneSucceeds() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        let pit = GridCoord(x: 3, y: 3, story: 0)
        placePit(in: &world, at: pit)
        world.setPlayerPosition(GridCoord(x: 3, y: 4, story: 0))

        let result = BridgePitUse.resolve(in: world)
        #expect(result?.seed == pit)
        #expect(result?.cells == [pit])
    }

    @Test func uniquePitAtDistanceTwoSucceeds() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        let pit = GridCoord(x: 3, y: 3, story: 0)
        placePit(in: &world, at: pit)
        world.setPlayerPosition(GridCoord(x: 3, y: 5, story: 0))

        let result = BridgePitUse.resolve(in: world)
        #expect(result?.seed == pit)
    }

    @Test func diagonalNeighborCountsAsOne() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        let pit = GridCoord(x: 3, y: 3, story: 0)
        placePit(in: &world, at: pit)
        world.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))

        let result = BridgePitUse.resolve(in: world)
        #expect(result?.seed == pit)
        #expect(BridgePitUse.chebyshev(GridCoord(x: 2, y: 2, story: 0), pit) == 1)
    }

    @Test func twoPitsInRangeFail() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        placePit(in: &world, at: GridCoord(x: 2, y: 2, story: 0))
        placePit(in: &world, at: GridCoord(x: 2, y: 4, story: 0))
        world.setPlayerPosition(GridCoord(x: 2, y: 3, story: 0))
        #expect(BridgePitUse.resolve(in: world) == nil)
    }

    @Test func nearPitWinsWhenOtherIsFar() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        let near = GridCoord(x: 2, y: 2, story: 0)
        placePit(in: &world, at: near)
        placePit(in: &world, at: GridCoord(x: 2, y: 6, story: 0))
        world.setPlayerPosition(GridCoord(x: 2, y: 3, story: 0))

        let result = BridgePitUse.resolve(in: world)
        #expect(result?.seed == near)
    }

    @Test func twoCellsOfOneBlobAreOneGroup() {
        var world = TestWorldFactory.emptyFloor(width: 7, height: 7)
        let a = GridCoord(x: 3, y: 3, story: 0)
        let b = GridCoord(x: 4, y: 3, story: 0)
        placePit(in: &world, at: a)
        placePit(in: &world, at: b)
        world.setPlayerPosition(GridCoord(x: 3, y: 4, story: 0))

        let result = BridgePitUse.resolve(in: world)
        #expect(result != nil)
        #expect(Set(result?.cells ?? []) == [a, b])
        #expect(BridgePitUse.pitGroups(in: world, story: 0).count == 1)
    }

    @Test func fadeCoordsIncludeBlobAndFloorNeighbors() throws {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let pit = GridCoord(x: 2, y: 2, story: 0)
        placePit(in: &world, at: pit)
        world.setPlayerPosition(GridCoord(x: 2, y: 3, story: 0))

        let result = try #require(BridgePitUse.resolve(in: world))
        let fade = Set(BridgePitUse.fadeCoords(for: result, in: world))
        #expect(fade.contains(pit))
        #expect(fade.contains(GridCoord(x: 2, y: 1, story: 0)))
        #expect(fade.contains(GridCoord(x: 1, y: 2, story: 0)))
        #expect(fade.contains(GridCoord(x: 3, y: 2, story: 0)))
        #expect(fade.contains(GridCoord(x: 2, y: 3, story: 0)))
    }

    private func placePit(in world: inout GameWorld, at coord: GridCoord) {
        world.setTile(Tile(kind: .floor(isPit: true)), at: coord)
    }
}
