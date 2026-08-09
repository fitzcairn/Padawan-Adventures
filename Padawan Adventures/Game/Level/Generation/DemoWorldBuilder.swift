import Foundation

/// Fixed three-room layout used when `AppConfig.demoMode` is true.
///
/// Room 0 is empty (player spawn). Room 1 has one pit per pit minigame kind.
/// Room 2 has one enemy per combat kind covering every enemy type, pickups, and treasure.
/// The wall between rooms 0 and 1 holds one 2-tile gate strip per gate minigame kind.
nonisolated enum DemoWorldBuilder {
    static let mapWidth = 25
    static let mapHeight = 15
    static let seed: UInt64 = 1

    /// Rooms and doorway cells matching the layout `build` produces (for validation/tests).
    nonisolated struct Layout: Equatable, Sendable {
        var rooms: [GeneratedRoom]
        var doorwayCells: Set<GridCoord>
        var spawn: GridCoord
    }

    static func layout() -> Layout {
        let rooms = [
            makeRoom(id: 0, xRange: 1...7, yRange: 1...13, center: GridCoord(x: 4, y: 7, story: 0)),
            makeRoom(id: 1, xRange: 9...15, yRange: 1...13, center: GridCoord(x: 12, y: 7, story: 0)),
            makeRoom(id: 2, xRange: 17...23, yRange: 1...13, center: GridCoord(x: 20, y: 7, story: 0)),
        ]
        let doorwayCells: Set<GridCoord> = [
            GridCoord(x: 16, y: 7, story: 0),
            GridCoord(x: 16, y: 8, story: 0),
        ]
        return Layout(rooms: rooms, doorwayCells: doorwayCells, spawn: GridCoord(x: 4, y: 7, story: 0))
    }

    static func build(
        level: LevelConfig,
        playerConfig: PlayerConfig,
        enemyConfig: EnemyConfig,
        floorTileSet: FloorTileSet?
    ) -> GameWorld {
        let layout = layout()
        var tiles: [[[Tile]]] = [
            Array(
                repeating: Array(repeating: Tile(kind: .wall), count: mapWidth),
                count: mapHeight
            ),
        ]

        for room in layout.rooms {
            for cell in room.cells {
                tiles[0][cell.y][cell.x] = Tile(kind: .floor(isPit: false))
            }
        }

        // Gate strips between rooms 0 and 1 (wall column x = 8).
        let gateKinds = level.gate.minigames.map(\.kind).prefix(4)
        for (index, kind) in gateKinds.enumerated() {
            let y0 = 2 + 3 * index
            let y1 = y0 + 1
            tiles[0][y0][8] = Tile(kind: .gate(minigame: kind))
            tiles[0][y1][8] = Tile(kind: .gate(minigame: kind))
        }

        // Isolated pits in room 1.
        let pitKinds = level.pit.minigames.map(\.kind).prefix(3)
        for (index, kind) in pitKinds.enumerated() {
            let y = 3 + 4 * index
            tiles[0][y][12] = Tile(kind: .floor(isPit: true), pitMinigame: kind)
        }

        // Open doorway between rooms 1 and 2 (wall column x = 16).
        for cell in layout.doorwayCells {
            tiles[0][cell.y][cell.x] = Tile(kind: .floor(isPit: false))
        }

        var entities: [GameEntity] = [
            GameEntity(
                letter: playerConfig.letter.first ?? "P",
                position: layout.spawn,
                isPlayer: true
            ),
        ]

        let combatKinds = level.combat.minigames.map(\.kind)
        let enemyTypes: [(id: String, config: EnemyTypeConfig)] = (level.enemies?.types ?? [])
            .compactMap { id in
                guard let typeConfig = enemyConfig.type(named: id) else { return nil }
                return (id, typeConfig)
            }

        if !enemyTypes.isEmpty {
            let candidates = [
                GridCoord(x: 18, y: 4, story: 0),
                GridCoord(x: 22, y: 4, story: 0),
                GridCoord(x: 18, y: 7, story: 0),
                GridCoord(x: 22, y: 7, story: 0),
                GridCoord(x: 18, y: 10, story: 0),
                GridCoord(x: 22, y: 10, story: 0),
                GridCoord(x: 20, y: 4, story: 0),
                GridCoord(x: 20, y: 10, story: 0),
            ]
            let count = min(max(combatKinds.count, enemyTypes.count), candidates.count)
            for index in 0..<count {
                let type = enemyTypes[index % enemyTypes.count]
                let combatKind = combatKinds.isEmpty
                    ? nil
                    : combatKinds[index % combatKinds.count]
                entities.append(
                    GameEntity(
                        letter: type.config.letterCharacter,
                        position: candidates[index],
                        isPlayer: false,
                        enemyTypeID: type.id,
                        combatMinigame: combatKind
                    )
                )
            }
        }

        entities.append(
            GameEntity(
                letter: " ",
                position: GridCoord(x: 18, y: 2, story: 0),
                pickupKind: .health
            )
        )
        if EnergyMechanic.isEnabled {
            entities.append(
                GameEntity(
                    letter: " ",
                    position: GridCoord(x: 22, y: 12, story: 0),
                    pickupKind: .energy
                )
            )
        }
        entities.append(
            GameEntity(
                letter: " ",
                position: GridCoord(x: 20, y: 7, story: 0),
                pickupKind: .treasure
            )
        )

        if let floorTileSet {
            var rng = SeededGenerator(seed: seed ^ FloorTiler.seedSalt)
            FloorTiler.tile(
                tiles: &tiles[0],
                story: 0,
                set: floorTileSet,
                options: FloorTiler.Options(
                    decorProb: level.floor.decorProb,
                    cohesion: level.floor.cohesion
                ),
                rooms: layout.rooms,
                rng: &rng
            )
        }

        return GameWorld(
            width: mapWidth,
            height: mapHeight,
            storyCount: 1,
            tiles: tiles,
            entities: entities,
            spawn: layout.spawn,
            healthCount: playerConfig.startingHealth,
            energyCount: playerConfig.startingEnergy,
            floorSet: floorTileSet,
            decorProb: level.floor.decorProb,
            cohesion: level.floor.cohesion,
            tileSeed: seed ^ FloorTiler.seedSalt
        )
    }

    private static func makeRoom(
        id: Int,
        xRange: ClosedRange<Int>,
        yRange: ClosedRange<Int>,
        center: GridCoord
    ) -> GeneratedRoom {
        var cells = Set<GridCoord>()
        for x in xRange {
            for y in yRange {
                cells.insert(GridCoord(x: x, y: y, story: 0))
            }
        }
        return GeneratedRoom(id: id, cells: cells, center: center, latticeX: 0, latticeY: 0)
    }
}
