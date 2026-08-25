import Foundation
import Testing
@testable import Padawan_Adventures

struct SatelliteScanUseTests {
    @Test func artifactCoordFindsTreasure() {
        var world = TestWorldFactory.emptyFloor(width: 8, height: 8)
        world.setPlayerPosition(GridCoord(x: 1, y: 1, story: 0))
        #expect(SatelliteScanUse.artifactCoord(in: world) == nil)

        let treasure = GameEntity(
            letter: " ",
            position: GridCoord(x: 5, y: 4, story: 0),
            pickupKind: .treasure
        )
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: world.entities + [treasure],
            spawn: world.spawn
        )
        #expect(SatelliteScanUse.artifactCoord(in: world) == treasure.position)
    }

    @Test func ringZeroIsTheOrigin() {
        let world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let origin = GridCoord(x: 2, y: 2, story: 0)
        #expect(SatelliteScanUse.ring(origin: origin, distance: 0, in: world) == [origin])
    }

    @Test func ringOneIsChebyshevNeighbors() {
        let world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let origin = GridCoord(x: 2, y: 2, story: 0)
        let ring = Set(SatelliteScanUse.ring(origin: origin, distance: 1, in: world))
        #expect(ring.count == 8)
        #expect(ring.contains(GridCoord(x: 3, y: 3, story: 0)))
        #expect(!ring.contains(origin))
    }

    @Test func floorsToRevealSkipsWalls() {
        var world = TestWorldFactory.emptyFloor(width: 5, height: 5)
        let origin = GridCoord(x: 2, y: 2, story: 0)
        world.setTile(Tile(kind: .wall), at: GridCoord(x: 3, y: 2, story: 0))
        let floors = SatelliteScanUse.floorsToReveal(origin: origin, distance: 1, in: world)
        #expect(!floors.contains(GridCoord(x: 3, y: 2, story: 0)))
        #expect(floors.contains(GridCoord(x: 2, y: 3, story: 0)))
    }

    @Test func scanRadiusIsFiveTiles() {
        #expect(SatelliteScanUse.itemID == "merchant-ware-satelite")
        #expect(SatelliteScanUse.radius == 5)
        let world = TestWorldFactory.emptyFloor(width: 13, height: 13)
        let origin = GridCoord(x: 6, y: 6, story: 0)
        #expect(SatelliteScanUse.ring(origin: origin, distance: 5, in: world).count == 40)
    }

    @Test func scannedFloorsRoundTrip() throws {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        world.revealScannedFloors([
            GridCoord(x: 2, y: 1, story: 0),
            GridCoord(x: 3, y: 3, story: 0),
        ])
        let data = try PropertyListEncoder().encode(world)
        let restored = try PropertyListDecoder().decode(GameWorld.self, from: data)
        #expect(restored.scannedFloorCells == world.scannedFloorCells)
    }
}
