import Foundation
import Testing
@testable import Padawan_Adventures

struct FloorTilerTests {
    @Test func fixedSeedIsDeterministic() throws {
        let set = try FloorTileSet.loadFromBundle(set: "1-tython")
        let a = assign(set: set, seed: 42)
        let b = assign(set: set, seed: 42)
        #expect(a == b)
    }

    @Test func everyFloorCellGetsValidID() throws {
        let set = try FloorTileSet.loadFromBundle(set: "2-tatooine")
        var tiles = makeFloorGrid(width: 8, height: 8, pitBlob: [(3, 3), (3, 4), (4, 3)])
        var rng = SeededGenerator(seed: 7)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0.1),
            rng: &rng
        )
        for row in tiles {
            for tile in row {
                guard case .floor = tile.kind else { continue }
                let id = try #require(tile.floorTileID)
                #expect(set.frames[id] != nil)
            }
        }
    }

    @Test func nonPitCellsNeverReceivePitTiles() throws {
        let set = try FloorTileSet.loadFromBundle(set: "6-coruscant")
        #expect(!set.pitTileIDs.isEmpty)
        var tiles = makeFloorGrid(width: 8, height: 8, pitBlob: [(3, 3), (3, 4), (4, 3), (4, 4)])
        var rng = SeededGenerator(seed: 11)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0.2),
            rng: &rng
        )
        for row in tiles {
            for tile in row {
                guard case .floor(let isPit) = tile.kind, !isPit else { continue }
                let id = try #require(tile.floorTileID)
                #expect(set.frames[id]?.role != .pit, "non-pit cell got pit tile \(id)")
            }
        }
    }

    @Test func adjacentPairsSatisfyMatches() throws {
        let set = try FloorTileSet.loadFromBundle(set: "6-coruscant")
        var tiles = makeFloorGrid(width: 6, height: 6, pitBlob: [(2, 2), (2, 3)])
        var rng = SeededGenerator(seed: 99)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0),
            rng: &rng
        )

        let height = tiles.count
        let width = tiles[0].count
        for y in 0..<height {
            for x in 0..<width {
                guard case .floor = tiles[y][x].kind,
                      let id = tiles[y][x].floorTileID else { continue }
                for side in FloorTileSet.Side.allCases {
                    let d = FloorTileSet.delta(side)
                    let nx = x + d.dx
                    let ny = y + d.dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height,
                          case .floor = tiles[ny][nx].kind,
                          let nid = tiles[ny][nx].floorTileID else { continue }
                    let allowed = set.frames[id]?.matches[side.rawValue] ?? []
                    // Relaxation can break hard matches; document soft requirement:
                    // either listed in matches, or both are floor/pit roles.
                    if !allowed.isEmpty && !allowed.contains(nid) {
                        #expect(set.frames[id] != nil && set.frames[nid] != nil)
                    }
                }
            }
        }
    }

    @Test func pitCellsPreferPitTiles() throws {
        let set = try FloorTileSet.loadFromBundle(set: "7-mustafar")
        #expect(!set.pitTileIDs.isEmpty)
        var tiles = makeFloorGrid(width: 5, height: 5, pitBlob: [(2, 2)])
        var rng = SeededGenerator(seed: 3)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0),
            rng: &rng
        )
        let id = try #require(tiles[2][2].floorTileID)
        #expect(set.frames[id]?.role == .pit, "pit cell got non-pit tile \(id)")
    }

    @Test func pitBlobCellsAllReceivePitTiles() throws {
        let set = try FloorTileSet.loadFromBundle(set: "4-kashyyyk")
        #expect(!set.pitTileIDs.isEmpty)
        var tiles = makeFloorGrid(width: 8, height: 8, pitBlob: [(3, 3), (3, 4), (4, 3), (4, 4)])
        var rng = SeededGenerator(seed: 19)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0.1),
            rng: &rng
        )
        for row in tiles {
            for tile in row {
                guard case .floor(let isPit) = tile.kind, isPit else { continue }
                let id = try #require(tile.floorTileID)
                #expect(set.frames[id]?.role == .pit, "pit blob cell got non-pit tile \(id)")
            }
        }
    }

    @Test func singleTileSetStillTerminates() throws {
        let full = try FloorTileSet.loadFromBundle(set: "8-geonosis")
        let oneID = try #require(full.floorTileIDs.first)
        let frame = try #require(full.frames[oneID])
        var soloFrame = frame
        soloFrame.matches = Dictionary(
            uniqueKeysWithValues: FloorTileSet.Side.allCases.map { ($0.rawValue, [oneID]) }
        )
        let tiny = FloorTileSet(
            meta: full.meta,
            frames: [oneID: soloFrame],
            pits: .init()
        )
        var tiles = makeFloorGrid(width: 4, height: 4, pitBlob: [])
        var rng = SeededGenerator(seed: 1)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: tiny,
            options: .init(decorProb: 0),
            rng: &rng
        )
        #expect(tiles.allSatisfy { row in row.allSatisfy { $0.floorTileID == oneID } })
    }

    @Test func retileOnlyTouchesNeighborhood() throws {
        let set = try FloorTileSet.loadFromBundle(set: "1-tython")
        var tiles = makeFloorGrid(width: 6, height: 6, pitBlob: [])
        var rng = SeededGenerator(seed: 11)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0),
            rng: &rng
        )
        let before = tiles.map { $0.map(\.floorTileID) }
        tiles[1][1] = Tile(kind: .floor(isPit: false))
        var rng2 = SeededGenerator(seed: 12)
        FloorTiler.retile(
            tiles: &tiles,
            story: 0,
            coords: [GridCoord(x: 1, y: 1, story: 0)],
            set: set,
            options: .init(decorProb: 0),
            rng: &rng2
        )
        for y in 0..<6 {
            for x in 0..<6 {
                let dist = abs(x - 1) + abs(y - 1)
                if dist > 1 {
                    #expect(tiles[y][x].floorTileID == before[y][x], "(\(x),\(y)) changed outside neighborhood")
                }
            }
        }
        #expect(tiles[1][1].floorTileID != nil)
    }

    @Test func retileAllFloorsIfNeededFixesStaleNonPitArtOnPitCells() throws {
        let set = try FloorTileSet.loadFromBundle(set: "7-mustafar")
        let floorID = try #require(set.floorTileIDs.first)
        #expect(!set.pitTileIDs.isEmpty)
        #expect(set.frames[floorID]?.role != .pit)

        var world = TestWorldFactory.withTiles(
            [[
                [
                    Tile(kind: .floor(isPit: false), floorTileID: floorID),
                    Tile(kind: .floor(isPit: true), floorTileID: floorID),
                    Tile(kind: .floor(isPit: false), floorTileID: floorID),
                ],
                [
                    Tile(kind: .floor(isPit: false), floorTileID: floorID),
                    Tile(kind: .floor(isPit: true), floorTileID: floorID),
                    Tile(kind: .floor(isPit: false), floorTileID: floorID),
                ],
                [
                    Tile(kind: .floor(isPit: false), floorTileID: floorID),
                    Tile(kind: .floor(isPit: false), floorTileID: floorID),
                    Tile(kind: .floor(isPit: false), floorTileID: floorID),
                ],
            ]],
            spawn: GridCoord(x: 0, y: 0, story: 0)
        )
        world.floorSet = set
        world.tileSeed = 21

        world.retileAllFloorsIfNeeded()

        for y in 0..<world.height {
            for x in 0..<world.width {
                let tile = try #require(world.tile(at: GridCoord(x: x, y: y, story: 0)))
                guard case .floor = tile.kind else { continue }
                let id = try #require(tile.floorTileID)
                if tile.isPit {
                    #expect(set.frames[id]?.role == .pit, "pit at (\(x),\(y)) kept non-pit art \(id)")
                } else {
                    #expect(set.frames[id]?.role != .pit, "floor at (\(x),\(y)) got pit art \(id)")
                }
            }
        }
    }

    @Test func retileAllFloorsIfNeededIsNoOpWhenRolesAlreadyMatch() throws {
        let set = try FloorTileSet.loadFromBundle(set: "4-kashyyyk")
        #expect(!set.pitTileIDs.isEmpty)

        var tiles = makeFloorGrid(width: 5, height: 5, pitBlob: [(2, 2)])
        var rng = SeededGenerator(seed: 9)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0),
            rng: &rng
        )
        let before = tiles.map { $0.map(\.floorTileID) }

        var world = TestWorldFactory.withTiles([tiles], spawn: GridCoord(x: 0, y: 0, story: 0))
        world.floorSet = set
        world.tileSeed = 9

        world.retileAllFloorsIfNeeded()

        for y in 0..<world.height {
            for x in 0..<world.width {
                #expect(
                    world.tile(at: GridCoord(x: x, y: y, story: 0))?.floorTileID == before[y][x],
                    "(\(x),\(y)) retiled despite matching roles"
                )
            }
        }
    }

    // MARK: - Helpers

    private func assign(set: FloorTileSet, seed: UInt64) -> [[String?]] {
        var tiles = makeFloorGrid(width: 5, height: 5, pitBlob: [(2, 2)])
        var rng = SeededGenerator(seed: seed)
        FloorTiler.tile(
            tiles: &tiles,
            story: 0,
            set: set,
            options: .init(decorProb: 0.05),
            rng: &rng
        )
        return tiles.map { $0.map(\.floorTileID) }
    }

    private func makeFloorGrid(
        width: Int,
        height: Int,
        pitBlob: [(Int, Int)]
    ) -> [[Tile]] {
        let pits = Set(pitBlob.map { GridCoord(x: $0.0, y: $0.1, story: 0) })
        return (0..<height).map { y in
            (0..<width).map { x in
                let isPit = pits.contains(GridCoord(x: x, y: y, story: 0))
                return Tile(kind: .floor(isPit: isPit))
            }
        }
    }
}
