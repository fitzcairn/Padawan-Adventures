import Foundation

nonisolated extension ProceduralGenerator {
    /// Force-places any missing required interactables (chance rolls already applied).
    func ensureRequiredInteractables(
        rooms: [GeneratedRoom],
        excludingRoomID: Int,
        spawn: GridCoord,
        tiles: inout [[[Tile]]],
        entities: inout [GameEntity],
        occupied: inout Set<GridCoord>,
        config: WorldGenerationConfig,
        enemyConfig: EnemyConfig,
        doorways: inout Set<GridCoord>,
        gateBag: inout WeightedPicker.Bag<GateMinigameKind>,
        pitBag: inout WeightedPicker.Bag<PitMinigameKind>,
        combatBag: inout WeightedPicker.Bag<CombatMinigameKind>,
        rng: inout SeededGenerator
    ) {
        let missing = Self.missingRequiredInteractables(tiles: tiles, entities: entities)
        guard !missing.isEmpty else { return }

        if missing.contains(.gate) {
            forceOneGate(
                rooms: rooms,
                in: &tiles[0],
                gateBag: &gateBag,
                doorways: &doorways,
                rng: &rng
            )
        }

        if missing.contains(.pit) {
            forceOnePit(
                rooms: rooms,
                into: &tiles[0],
                meanSize: config.generation.room.pitMeanSize,
                maxSize: config.generation.room.pitMaxSize,
                excludingRoomID: excludingRoomID,
                excluding: occupied.union([spawn]),
                pitBag: &pitBag,
                rng: &rng
            )
            clearPits(around: spawn, tiles: &tiles, story: 0)
        }

        if missing.contains(.enemy) {
            if let enemy = forceOneEnemy(
                in: rooms,
                excludingRoomID: excludingRoomID,
                tiles: tiles,
                config: config,
                enemyConfig: enemyConfig,
                occupied: &occupied,
                combatBag: &combatBag,
                rng: &rng
            ) {
                entities.append(enemy)
            }
        }
    }

    /// Places a single enemy when the probabilistic pass produced none.
    func forceOneEnemy(
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        config: WorldGenerationConfig,
        enemyConfig: EnemyConfig,
        occupied: inout Set<GridCoord>,
        combatBag: inout WeightedPicker.Bag<CombatMinigameKind>,
        rng: inout SeededGenerator
    ) -> GameEntity? {
        let resolvedTypes: [(id: String, config: EnemyTypeConfig)]
        if let spawnConfig = config.enemies {
            let fromConfig: [(id: String, config: EnemyTypeConfig)] = spawnConfig.types.compactMap { id in
                guard let configured = enemyConfig.type(named: id) else { return nil }
                return (id, configured)
            }
            if !fromConfig.isEmpty {
                resolvedTypes = fromConfig
            } else if let first = enemyConfig.enemies.sorted(by: { $0.key < $1.key }).first {
                resolvedTypes = [(first.key, first.value)]
            } else {
                return nil
            }
        } else if let first = enemyConfig.enemies.sorted(by: { $0.key < $1.key }).first {
            resolvedTypes = [(first.key, first.value)]
        } else {
            return nil
        }

        let ordered = rooms.sorted { $0.id < $1.id }
        for room in ordered where room.id != excludingRoomID {
            guard let position = pickRoomFloorCell(
                in: room,
                tiles: tiles,
                occupied: occupied,
                rng: &rng
            ) else { continue }

            let pick = Self.pickEnemyType(from: resolvedTypes, rng: &rng)
            occupied.insert(position)
            return GameEntity(
                letter: pick.config.letterCharacter,
                position: position,
                isPlayer: false,
                enemyTypeID: pick.id,
                combatMinigame: combatBag.next(using: &rng)
            )
        }
        return nil
    }

    /// One roll per room (except the spawn room); place on a room floor cell only.
    /// When multiple types are configured, each spawn picks uniformly among them.
    func spawnEnemies(
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        types: [(id: String, config: EnemyTypeConfig)],
        chance: Double,
        occupied: inout Set<GridCoord>,
        combatBag: inout WeightedPicker.Bag<CombatMinigameKind>,
        rng: inout SeededGenerator
    ) -> [GameEntity] {
        var enemies: [GameEntity] = []
        guard !types.isEmpty else { return enemies }

        for room in rooms where room.id != excludingRoomID {
            guard rng.nextBool(probability: chance) else { continue }
            guard let position = pickRoomFloorCell(
                in: room,
                tiles: tiles,
                occupied: occupied,
                rng: &rng
            ) else { continue }

            let pick = Self.pickEnemyType(from: types, rng: &rng)
            occupied.insert(position)
            enemies.append(
                GameEntity(
                    letter: pick.config.letterCharacter,
                    position: position,
                    isPlayer: false,
                    enemyTypeID: pick.id,
                    combatMinigame: combatBag.next(using: &rng)
                )
            )
        }

        return enemies
    }

    /// Single-type lists skip the RNG draw so spawn streams stay stable vs legacy `type:`.
    static func pickEnemyType(
        from types: [(id: String, config: EnemyTypeConfig)],
        rng: inout SeededGenerator
    ) -> (id: String, config: EnemyTypeConfig) {
        if types.count == 1 {
            return types[0]
        }
        return types[rng.nextInt(upperBound: types.count)]
    }

    /// Places pickups by `count` (preferred) or one roll per room; never the spawn room.
    ///
    /// Never places two pickups on the same or orthogonally adjacent tiles.
    func spawnPickups(
        _ config: LevelConfig.PickupsSpawnConfig,
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        pickupCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> [GameEntity] {
        var pickups: [GameEntity] = []
        var kinds: [(PickupKind, LevelConfig.PickupChanceConfig?)] = [
            (.health, config.health),
        ]
        if EnergyMechanic.isEnabled {
            kinds.append((.energy, config.energy))
        }

        for (kind, spec) in kinds {
            guard let spec else { continue }
            if let count = spec.count {
                pickups.append(contentsOf: spawnCountedPickups(
                    kind: kind,
                    count: count,
                    in: rooms,
                    excludingRoomID: excludingRoomID,
                    tiles: tiles,
                    occupied: &occupied,
                    pickupCells: &pickupCells,
                    rng: &rng
                ))
            } else if let chance = spec.spawnChancePerRoom {
                for room in rooms where room.id != excludingRoomID {
                    guard rng.nextBool(probability: chance) else { continue }
                    if let pickup = placePickup(
                        kind: kind,
                        in: room,
                        tiles: tiles,
                        occupied: &occupied,
                        pickupCells: &pickupCells,
                        rng: &rng
                    ) {
                        pickups.append(pickup)
                    }
                }
            }
        }

        return pickups
    }

    /// Shuffles non-spawn rooms and places up to `count` pickups (one per room first).
    func spawnCountedPickups(
        kind: PickupKind,
        count: Int,
        in rooms: [GeneratedRoom],
        excludingRoomID: Int,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        pickupCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> [GameEntity] {
        guard count > 0 else { return [] }
        var eligible = rooms.filter { $0.id != excludingRoomID }
        if eligible.count > 1 {
            for i in stride(from: eligible.count - 1, through: 1, by: -1) {
                eligible.swapAt(i, rng.nextInt(upperBound: i + 1))
            }
        }

        var pickups: [GameEntity] = []
        func tryPlace(in room: GeneratedRoom) -> Bool {
            guard pickups.count < count else { return false }
            guard let pickup = placePickup(
                kind: kind,
                in: room,
                tiles: tiles,
                occupied: &occupied,
                pickupCells: &pickupCells,
                rng: &rng
            ) else { return false }
            pickups.append(pickup)
            return true
        }

        for room in eligible {
            _ = tryPlace(in: room)
        }
        while pickups.count < count {
            var placedThisRound = false
            for room in eligible {
                if tryPlace(in: room) {
                    placedThisRound = true
                }
            }
            if !placedThisRound { break }
        }
        return pickups
    }

    func placePickup(
        kind: PickupKind,
        in room: GeneratedRoom,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        pickupCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GameEntity? {
        guard let position = pickVisiblePickupFloorCell(
            in: room,
            tiles: tiles,
            occupied: occupied,
            pickupCells: pickupCells,
            rng: &rng
        ) else { return nil }

        occupied.insert(position)
        pickupCells.insert(position)
        return GameEntity(
            letter: " ",
            position: position,
            isPlayer: false,
            pickupKind: kind
        )
    }

    /// Places exactly one treasure on a visible floor tile in the farthest room that has one.
    func spawnTreasure(
        in rooms: [GeneratedRoom],
        spawn: GridCoord,
        tiles: [[[Tile]]],
        occupied: inout Set<GridCoord>,
        pickupCells: inout Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GameEntity? {
        let ordered = rooms.sorted { lhs, rhs in
            let lhsDist = manhattan(spawn, lhs.center)
            let rhsDist = manhattan(spawn, rhs.center)
            if lhsDist != rhsDist { return lhsDist > rhsDist }
            return lhs.id > rhs.id
        }

        for room in ordered {
            guard let position = pickVisiblePickupFloorCell(
                in: room,
                tiles: tiles,
                occupied: occupied,
                pickupCells: pickupCells,
                rng: &rng
            ) else { continue }

            occupied.insert(position)
            pickupCells.insert(position)
            return GameEntity(
                letter: " ",
                position: position,
                isPlayer: false,
                pickupKind: .treasure
            )
        }
        return nil
    }

    /// Picks a cell for enemies: room floor only (never pit, gate, wall, or hallway).
    func pickRoomFloorCell(
        in room: GeneratedRoom,
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GridCoord? {
        let candidates = room.cells
            .filter { cell in
                guard !occupied.contains(cell) else { return false }
                return isEntityPlaceableRoomFloor(cell, in: room, tiles: tiles)
            }
            .sorted { lhs, rhs in
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.y < rhs.y
            }
        return rng.pick(candidates)
    }

    /// Picks a pickup cell in full view and at least one tile from any wall/gate.
    ///
    /// Also skips cells that share an edge with an already-placed pickup.
    func pickVisiblePickupFloorCell(
        in room: GeneratedRoom,
        tiles: [[[Tile]]],
        occupied: Set<GridCoord>,
        pickupCells: Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> GridCoord? {
        let candidates = room.cells
            .filter { cell in
                guard !occupied.contains(cell) else { return false }
                guard !isOrthogonallyAdjacent(cell, toAnyIn: pickupCells) else { return false }
                guard isEntityPlaceableRoomFloor(cell, in: room, tiles: tiles) else { return false }
                return !IsometricTileGeometry.isAdjacentToOpaqueOccluder(at: cell, in: tiles[0])
            }
            .sorted { lhs, rhs in
                if lhs.x != rhs.x { return lhs.x < rhs.x }
                return lhs.y < rhs.y
            }
        return rng.pick(candidates)
    }

    /// True when `cell` shares an edge with any coord in `others` (same story).
    func isOrthogonallyAdjacent(_ cell: GridCoord, toAnyIn others: Set<GridCoord>) -> Bool {
        for (dx, dy) in GridCoord.cardinals {
            if others.contains(cell.neighbor(dx: dx, dy: dy)) {
                return true
            }
        }
        return false
    }

    /// True only for non-pit floor tiles inside the given room (pickups and enemy sprites).
    func isEntityPlaceableRoomFloor(
        _ cell: GridCoord,
        in room: GeneratedRoom,
        tiles: [[[Tile]]]
    ) -> Bool {
        guard room.cells.contains(cell) else { return false }
        guard cell.y >= 0, cell.y < tiles[0].count else { return false }
        guard cell.x >= 0, cell.x < tiles[0][cell.y].count else { return false }
        switch tiles[0][cell.y][cell.x].kind {
        case .floor(let isPit):
            return !isPit
        case .gate(_), .wall:
            return false
        }
    }

    func runEntitiesPass(
        state: inout GenerationAttemptState,
        config: WorldGenerationConfig,
        playerConfig: PlayerConfig,
        enemyConfig: EnemyConfig
    ) {
        let letter = playerConfig.letter.first ?? "P"
        let player = GameEntity(letter: letter, position: state.spawn, isPlayer: true)
        state.entities = [player]
        state.occupied = [state.spawn]
        state.pickupCells = []

        if let spawnConfig = config.enemies {
            let resolvedTypes: [(id: String, config: EnemyTypeConfig)] = spawnConfig.types.compactMap { id in
                guard let typeConfig = enemyConfig.type(named: id) else { return nil }
                return (id, typeConfig)
            }
            if !resolvedTypes.isEmpty {
                let enemies = spawnEnemies(
                    in: state.rooms,
                    excludingRoomID: state.topRight.id,
                    tiles: state.tiles,
                    types: resolvedTypes,
                    chance: spawnConfig.spawnChancePerRoom,
                    occupied: &state.occupied,
                    combatBag: &state.combatBag,
                    rng: &state.rng
                )
                state.entities.append(contentsOf: enemies)
            }
        }

        if let pickups = config.pickups {
            let spawned = spawnPickups(
                pickups,
                in: state.rooms,
                excludingRoomID: state.topRight.id,
                tiles: state.tiles,
                occupied: &state.occupied,
                pickupCells: &state.pickupCells,
                rng: &state.rng
            )
            state.entities.append(contentsOf: spawned)
        }

        if let treasure = spawnTreasure(
            in: state.rooms,
            spawn: state.spawn,
            tiles: state.tiles,
            occupied: &state.occupied,
            pickupCells: &state.pickupCells,
            rng: &state.rng
        ) {
            state.entities.append(treasure)
        }
    }

    func runFinalizePass(
        state: inout GenerationAttemptState,
        config: WorldGenerationConfig,
        playerConfig: PlayerConfig,
        enemyConfig: EnemyConfig,
        floorTileSet: FloorTileSet,
        seed: UInt64
    ) {
        ensureRequiredInteractables(
            rooms: state.rooms,
            excludingRoomID: state.topRight.id,
            spawn: state.spawn,
            tiles: &state.tiles,
            entities: &state.entities,
            occupied: &state.occupied,
            config: config,
            enemyConfig: enemyConfig,
            doorways: &state.doorwayCells,
            gateBag: &state.gateBag,
            pitBag: &state.pitBag,
            combatBag: &state.combatBag,
            rng: &state.rng
        )

        var floorRng = SeededGenerator(seed: seed ^ FloorTiler.seedSalt)
        for storyIndex in state.tiles.indices {
            FloorTiler.tile(
                tiles: &state.tiles[storyIndex],
                story: storyIndex,
                set: floorTileSet,
                options: FloorTiler.Options(
                    decorProb: config.decorProb,
                    cohesion: config.cohesion
                ),
                rooms: state.rooms,
                rng: &floorRng
            )
        }
    }
}

nonisolated extension ProceduralGenerator {
    func runGenerationPass(
        _ pass: GenerationPass,
        state: inout GenerationAttemptState,
        config: WorldGenerationConfig,
        playerConfig: PlayerConfig,
        enemyConfig: EnemyConfig,
        floorTileSet: FloorTileSet,
        seed: UInt64
    ) {
        switch pass {
        case .rooms:
            runRoomsPass(state: &state, config: config)
        case .gates:
            runGatesPass(state: &state, config: config)
        case .pits:
            runPitsPass(state: &state, config: config)
        case .entities:
            runEntitiesPass(
                state: &state,
                config: config,
                playerConfig: playerConfig,
                enemyConfig: enemyConfig
            )
        case .finalize:
            runFinalizePass(
                state: &state,
                config: config,
                playerConfig: playerConfig,
                enemyConfig: enemyConfig,
                floorTileSet: floorTileSet,
                seed: seed
            )
        }
    }
}
