import Foundation
import Testing
@testable import Padawan_Adventures

struct DemoWorldBuilderTests {
    private func makeWorld() throws -> (GameWorld, LevelConfig, EnemyConfig) {
        let level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        let enemyConfig = try EnemyConfig.loadFromBundle()
        let world = DemoWorldBuilder.build(
            level: level,
            playerConfig: .fallback,
            enemyConfig: enemyConfig,
            floorTileSet: nil
        )
        return (world, level, enemyConfig)
    }

    @Test func buildsFixedDimensionsAndBorderWalls() throws {
        let (world, _, _) = try makeWorld()
        #expect(world.width == 25)
        #expect(world.height == 15)
        #expect(world.storyCount == 1)
        #expect(world.spawn == GridCoord(x: 4, y: 7, story: 0))

        for x in 0..<world.width {
            #expect(world.tile(at: GridCoord(x: x, y: 0, story: 0))?.isWall == true)
            #expect(world.tile(at: GridCoord(x: x, y: world.height - 1, story: 0))?.isWall == true)
        }
        for y in 0..<world.height {
            #expect(world.tile(at: GridCoord(x: 0, y: y, story: 0))?.isWall == true)
            #expect(world.tile(at: GridCoord(x: world.width - 1, y: y, story: 0))?.isWall == true)
        }
    }

    @Test func startRoomIsEmptyAsideFromPlayer() throws {
        let (world, _, _) = try makeWorld()
        let startCells = DemoWorldBuilder.layout().rooms[0].cells

        for entity in world.entities where !entity.isPlayer {
            if entity.isMerchant {
                #expect(entity.position == GridCoord(x: 1, y: 13, story: 0))
                continue
            }
            #expect(!startCells.contains(entity.position))
        }
        for cell in startCells {
            let tile = world.tile(at: cell)
            #expect(tile?.isPit != true)
            #expect(tile?.isGate != true)
        }
        let hasPlayer = world.entities.contains(where: \.isPlayer)
        #expect(hasPlayer)
        #expect(world.playerPosition == world.spawn)
    }

    @Test func placesMerchantInStartRoomCorner() throws {
        let (world, _, _) = try makeWorld()
        let merchants = world.entities.filter(\.isMerchant)
        #expect(merchants.count == 1)
        #expect(merchants.first?.position == GridCoord(x: 1, y: 13, story: 0))
        #expect(merchants.first?.isEnemy == false)
    }

    @Test func placesOneGateStripPerGateKind() throws {
        let (world, level, _) = try makeWorld()
        let gateKinds = level.gate.minigames.map(\.kind)

        for (index, kind) in gateKinds.enumerated() {
            let y0 = 2 + 3 * index
            let y1 = y0 + 1
            let a = GridCoord(x: 8, y: y0, story: 0)
            let b = GridCoord(x: 8, y: y1, story: 0)
            #expect(world.tile(at: a)?.gateMinigame == kind)
            #expect(world.tile(at: b)?.gateMinigame == kind)
            #expect(world.tile(at: GridCoord(x: 8, y: y0 - 1, story: 0))?.isWall == true)
            #expect(world.tile(at: GridCoord(x: 8, y: y1 + 1, story: 0))?.isWall == true)
        }

        var counts: [GateMinigameKind: Int] = [:]
        for y in 0..<world.height {
            for x in 0..<world.width {
                if let kind = world.tile(at: GridCoord(x: x, y: y, story: 0))?.gateMinigame {
                    counts[kind, default: 0] += 1
                }
            }
        }
        for kind in gateKinds {
            #expect(counts[kind] == 2)
        }
    }

    @Test func placesOneIsolatedPitPerPitKind() throws {
        let (world, level, _) = try makeWorld()
        let pitKinds = level.pit.minigames.map(\.kind)

        var pits: [(GridCoord, PitMinigameKind)] = []
        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: 0)
                guard let tile = world.tile(at: coord), tile.isPit else { continue }
                guard let kind = tile.pitMinigame else {
                    Issue.record("pit at \(coord) missing pitMinigame pin")
                    continue
                }
                pits.append((coord, kind))
            }
        }

        #expect(Set(pits.map(\.1)) == Set(pitKinds))
        #expect(pits.count == pitKinds.count)

        for (coord, _) in pits {
            for (dx, dy) in GridCoord.cardinals {
                let neighbor = coord.neighbor(dx: dx, dy: dy)
                #expect(world.tile(at: neighbor)?.isPit != true)
            }
        }
    }

    @Test func enemiesCoverCombatKindsAndEnemyTypes() throws {
        let (world, level, enemyConfig) = try makeWorld()
        let combatKinds = Set(level.combat.minigames.map(\.kind))
        let enemyTypes = Set(
            (level.enemies?.types ?? []).compactMap { id in
                enemyConfig.type(named: id) == nil ? nil : id
            }
        )
        let enemies = world.entities.filter(\.isEnemy)

        #expect(!enemies.isEmpty)
        #expect(enemies.allSatisfy { $0.combatMinigame != nil })
        #expect(Set(enemies.compactMap(\.combatMinigame)) == combatKinds)
        #expect(Set(enemies.compactMap(\.enemyTypeID)) == enemyTypes)
    }

    @Test func placesTreasureAndHealthAwayFromWalls() throws {
        let (world, _, _) = try makeWorld()
        let treasure = world.entities.first { $0.pickupKind == .treasure }
        #expect(treasure?.position == GridCoord(x: 20, y: 7, story: 0))
        #expect(world.entities.contains { $0.pickupKind == .health })

        for pickup in world.entities.filter(\.isPickup) {
            #expect(
                !IsometricTileGeometry.isAdjacentToOpaqueOccluder(
                    at: pickup.position,
                    in: world.tiles[0]
                )
            )
        }
    }

    @Test func layoutPassesGenerationValidation() throws {
        let (world, _, _) = try makeWorld()
        let layout = DemoWorldBuilder.layout()
        #expect(ProceduralGenerator.missingRequiredInteractables(in: world).isEmpty)
        #expect(
            ProceduralGenerator.allRoomsGateConnected(
                rooms: layout.rooms,
                spawn: layout.spawn,
                tiles: world.tiles[0]
            )
        )
        #expect(
            ProceduralGenerator.roomPassagesAreIntentional(
                rooms: layout.rooms,
                tiles: world.tiles[0],
                doorways: layout.doorwayCells
            )
        )
    }

    @Test func buildIsDeterministic() throws {
        let level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        let enemyConfig = try EnemyConfig.loadFromBundle()
        let a = DemoWorldBuilder.build(
            level: level,
            playerConfig: .fallback,
            enemyConfig: enemyConfig,
            floorTileSet: nil
        )
        let b = DemoWorldBuilder.build(
            level: level,
            playerConfig: .fallback,
            enemyConfig: enemyConfig,
            floorTileSet: nil
        )
        #expect(a.fingerprint() == b.fingerprint())
    }

    @Test func composeUsesDemoMapSizeWhenDemoModeEnabled() throws {
        let app = AppConfig(version: 1, seed: 1, demoMode: true)
        let level = try LevelConfig.loadFromBundle(
            named: "1-tython",
            subdirectory: LevelCatalog.subdirectory
        )
        let generation = WorldGenerationConfig.compose(app: app, level: level)
        #expect(generation.world.width == DemoWorldBuilder.mapWidth)
        #expect(generation.world.height == DemoWorldBuilder.mapHeight)
    }
}
