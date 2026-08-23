import Foundation
import Testing
@testable import Padawan_Adventures

struct MerchantSpawnerTests {
    @Test func roomHopsFollowJoinTree() {
        let hops = MerchantSpawner.roomHops(
            from: 2,
            joinEdges: [(0, 1), (1, 2)]
        )
        #expect(hops[2] == 0)
        #expect(hops[1] == 1)
        #expect(hops[0] == 2)
    }

    @Test func biasWeightsDecayWithHops() {
        #expect(MerchantSpawner.biasWeight(hops: 0) == 64)
        #expect(MerchantSpawner.biasWeight(hops: 1) == 16)
        #expect(MerchantSpawner.biasWeight(hops: 2) == 4)
        #expect(MerchantSpawner.biasWeight(hops: 5) == 1)
        #expect(MerchantSpawner.biasWeight(hops: 0) > MerchantSpawner.biasWeight(hops: 1))
    }

    @Test func biasedPickPrefersTreasureRoom() {
        let fixture = Fixture.lineOfThreeRooms()
        var treasureRoomHits = 0
        var adjacentHits = 0
        for seed in UInt64(1)...UInt64(160) {
            var rng = SeededGenerator(seed: seed)
            let cell = MerchantSpawner.pickCell(
                rooms: fixture.rooms,
                tiles: fixture.tiles,
                occupied: fixture.occupied,
                treasure: fixture.treasure,
                joinEdges: fixture.joinEdges,
                biasTowardTreasure: true,
                rng: &rng
            )
            guard let cell, let room = fixture.room(containing: cell) else { continue }
            if room.id == 2 { treasureRoomHits += 1 }
            if room.id == 1 { adjacentHits += 1 }
        }
        #expect(treasureRoomHits > 90)
        #expect(treasureRoomHits > adjacentHits)
    }

    @Test func demoStyleUniformPickDoesNotPreferTreasureRoom() {
        let fixture = Fixture.lineOfThreeRooms()
        var treasureRoomHits = 0
        for seed in UInt64(1)...UInt64(160) {
            var rng = SeededGenerator(seed: seed)
            let cell = MerchantSpawner.pickCell(
                rooms: fixture.rooms,
                tiles: fixture.tiles,
                occupied: fixture.occupied,
                treasure: fixture.treasure,
                joinEdges: fixture.joinEdges,
                biasTowardTreasure: false,
                rng: &rng
            )
            guard let cell, let room = fixture.room(containing: cell) else { continue }
            if room.id == 2 { treasureRoomHits += 1 }
        }
        #expect(treasureRoomHits < 90)
        #expect(treasureRoomHits > 20)
    }

    private struct Fixture {
        var rooms: [GeneratedRoom]
        var tiles: [[[Tile]]]
        var occupied: Set<GridCoord>
        var treasure: GridCoord
        var joinEdges: [(Int, Int)]

        func room(containing cell: GridCoord) -> GeneratedRoom? {
            rooms.first { $0.cells.contains(cell) }
        }

        static func lineOfThreeRooms() -> Fixture {
            let rooms = [
                rectangle(id: 0, xs: 1...4, ys: 1...4),
                rectangle(id: 1, xs: 7...10, ys: 1...4),
                rectangle(id: 2, xs: 13...16, ys: 1...4),
            ]
            let width = 18
            let height = 6
            let row = Array(repeating: Tile(kind: .floor(isPit: false)), count: width)
            let tiles = [Array(repeating: row, count: height)]
            let treasure = GridCoord(x: 14, y: 2, story: 0)
            return Fixture(
                rooms: rooms,
                tiles: tiles,
                occupied: [treasure],
                treasure: treasure,
                joinEdges: [(0, 1), (1, 2)]
            )
        }

        static func rectangle(id: Int, xs: ClosedRange<Int>, ys: ClosedRange<Int>) -> GeneratedRoom {
            var cells: Set<GridCoord> = []
            for x in xs {
                for y in ys {
                    cells.insert(GridCoord(x: x, y: y, story: 0))
                }
            }
            let center = GridCoord(
                x: (xs.lowerBound + xs.upperBound) / 2,
                y: (ys.lowerBound + ys.upperBound) / 2,
                story: 0
            )
            return GeneratedRoom(id: id, cells: cells, center: center, latticeX: 0, latticeY: 0)
        }
    }
}
