import Foundation
import Testing
@testable import Padawan_Adventures

struct GameSaveTests {
    private func makeSaveService() throws -> (GameSaveService, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let service = try GameSaveService(fileManager: .default, directoryURL: directory)
        return (service, directory)
    }

    @Test func roundTripPreservesWorld() async throws {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        world.setTile(Tile(kind: .gate(minigame: .spelling)), at: GridCoord(x: 2, y: 2, story: 0))
        _ = world.openGate(at: GridCoord(x: 2, y: 2, story: 0))
        world.setPlayerPosition(GridCoord(x: 3, y: 1, story: 0))

        let fingerprint = world.fingerprint()
        let playerPosition = world.playerPosition

        let (service, _) = try makeSaveService()
        try await service.save(world)
        let restored = try await service.load()

        #expect(restored != nil)
        #expect(restored?.fingerprint() == fingerprint)
        #expect(restored?.playerPosition == playerPosition)
    }

    @Test func roundTripPreservesPickupsAndHudCounts() async throws {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        let health = GameEntity(
            letter: " ",
            position: GridCoord(x: 1, y: 1, story: 0),
            pickupKind: .health
        )
        let treasure = GameEntity(
            letter: " ",
            position: GridCoord(x: 2, y: 2, story: 0),
            pickupKind: .treasure
        )
        world = GameWorld(
            width: world.width,
            height: world.height,
            storyCount: world.storyCount,
            tiles: world.tiles,
            entities: world.entities + [health, treasure],
            spawn: world.spawn,
            healthCount: 2,
            energyCount: 1
        )

        let (service, _) = try makeSaveService()
        try await service.save(world)
        let restored = try await service.load()

        #expect(restored?.healthCount == 2)
        #expect(restored?.energyCount == 1)
        let pickups = restored?.entities.filter(\.isPickup) ?? []
        #expect(pickups.count == 2)
        #expect(pickups.contains { $0.pickupKind == .health })
        #expect(pickups.contains { $0.pickupKind == .treasure })
    }

    @Test func tileKindRoundTripAllCases() throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoder = PropertyListDecoder()

        let kinds: [TileKind] = [
            .floor(isPit: false),
            .floor(isPit: true),
            .gate(minigame: .spelling),
            .wall,
            .gate(minigame: .letterMatch),
        ]

        for kind in kinds {
            let tile = Tile(kind: kind)
            let data = try encoder.encode(tile)
            let decoded = try decoder.decode(Tile.self, from: data)
            #expect(decoded == tile)
        }

        // Legacy bare gate (no minigame key) migrates to spelling.
        let legacyGateJSON = """
        {"kind":{"type":"gate"}}
        """.data(using: .utf8)!
        let legacyGate = try JSONDecoder().decode(Tile.self, from: legacyGateJSON)
        #expect(legacyGate.gateMinigame == .spelling)

        let withTile = Tile(kind: .floor(isPit: false), floorTileID: "r00c03")
        let tileData = try encoder.encode(withTile)
        let decodedTile = try decoder.decode(Tile.self, from: tileData)
        #expect(decodedTile == withTile)

        // Legacy saves that stored `terrainID` still decode into `floorTileID`.
        let legacyJSON = """
        {"kind":{"type":"floor","isPit":false},"terrainID":"grass","accentTerrainID":"flowers"}
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(Tile.self, from: legacyJSON)
        #expect(legacy.floorTileID == "grass")
    }

    @Test func legacyDoorWallDecodesAsFloor() throws {
        let json = """
        {"kind":{"type":"wall","destructible":false,"hasDoor":true}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Tile.self, from: json)
        if case .floor(let isPit) = decoded.kind {
            #expect(!isPit)
        } else {
            Issue.record("Expected legacy door to decode as floor")
        }
    }

    @Test func loadReturnsNilWhenMissing() async throws {
        let (service, _) = try makeSaveService()
        let loaded = try await service.load()
        #expect(loaded == nil)
    }

    @Test func saveCoalescesToLatest() async throws {
        var firstWorld = TestWorldFactory.emptyFloor(width: 3, height: 3)
        firstWorld.setPlayerPosition(GridCoord(x: 0, y: 0, story: 0))

        var secondWorld = TestWorldFactory.emptyFloor(width: 3, height: 3)
        secondWorld.setPlayerPosition(GridCoord(x: 2, y: 2, story: 0))

        let (service, _) = try makeSaveService()

        try await service.save(firstWorld)
        try await service.save(secondWorld)

        let restored = try await service.load()
        #expect(restored?.playerPosition == GridCoord(x: 2, y: 2, story: 0))
    }

    @Test func pauseSaveSnapshot() async throws {
        var world = TestWorldFactory.emptyFloor(width: 4, height: 4)
        var movement = MovementSystem()
        let destination = GridCoord(x: 2, y: 0, story: 0)
        let path = [
            GridCoord(x: 0, y: 0, story: 0),
            destination,
        ]

        movement.begin(path: path)
        #expect(movement.isMoving)

        _ = movement.update(deltaTime: 10, world: &world)
        #expect(movement.isMoving == false)
        #expect(world.playerPosition == destination)

        let (service, _) = try makeSaveService()
        try await service.save(world)

        let restored = try await service.load()
        #expect(restored?.playerPosition == destination)
    }
}
