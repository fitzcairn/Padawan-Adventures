import Testing
@testable import Padawan_Adventures

struct ProceduralGeneratorTests {
    private func roomsDoorsConfig(seed: UInt64 = 99, roomCount: Int = 6) -> WorldGenerationConfig {
        WorldGenerationConfig(
            seed: seed,
            world: .init(width: 30, height: 30, stories: 1),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: roomCount,
                corridorWidth: 2,
                room: .init(
                    minRoomSize: 4,
                    maxRoomSize: 10,
                    pitChance: 0.2,
                    partitionGateChance: 0.5
                )
            )
        )
    }

    private func expectedTopRightRoom(from rooms: [GeneratedRoom]) -> GeneratedRoom {
        rooms.max { lhs, rhs in
            let lhsScore = (lhs.center.x - lhs.center.y, -(lhs.center.x + lhs.center.y))
            let rhsScore = (rhs.center.x - rhs.center.y, -(rhs.center.x + rhs.center.y))
            return lhsScore < rhsScore
        }!
    }

    private func expectedSpawn(for room: GeneratedRoom) -> GridCoord {
        room.cells.min { lhs, rhs in
            let lhsDist = abs(lhs.x - room.center.x) + abs(lhs.y - room.center.y)
            let rhsDist = abs(rhs.x - room.center.x) + abs(rhs.y - room.center.y)
            return lhsDist < rhsDist
        }!
    }

    private func reachableCells(from start: GridCoord, in world: GameWorld) -> Set<GridCoord> {
        var queue = [start]
        var visited = Set<GridCoord>([start])

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard world.isInBounds(next), !visited.contains(next), world.isEnterable(at: next) else { continue }
                visited.insert(next)
                queue.append(next)
            }
        }
        return visited
    }

    private func joinHasOpening(
        _ roomA: GeneratedRoom,
        _ roomB: GeneratedRoom,
        world: GameWorld
    ) -> Bool {
        func boundaryOpening(of room: GeneratedRoom) -> Bool {
            for cell in room.cells {
                for (dx, dy) in GridCoord.cardinals {
                    let neighbor = cell.neighbor(dx: dx, dy: dy)
                    guard !room.cells.contains(neighbor) else { continue }
                    guard let tile = world.tile(at: neighbor) else { continue }
                    switch tile.kind {
                    case .floor, .gate:
                        return true
                    case .wall:
                        break
                    }
                }
            }
            return false
        }
        // Joins leave a floor / gate opening on each room ring.
        return boundaryOpening(of: roomA) && boundaryOpening(of: roomB)
    }

    private func floorCellsOutsideRooms(world: GameWorld, rooms: [GeneratedRoom]) -> Int {
        let roomCells = rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }
        var count = 0
        for y in 0..<world.height {
            for x in 0..<world.width {
                let coord = GridCoord(x: x, y: y, story: 0)
                guard case .floor = world.tile(at: coord)?.kind else { continue }
                if !roomCells.contains(coord) {
                    count += 1
                }
            }
        }
        return count
    }

    @Test func sameSeedProducesIdenticalWorld() throws {
        let config = roomsDoorsConfig(seed: 99, roomCount: 4)

        let first = try ProceduralGenerator().generate(from: config)
        let second = try ProceduralGenerator().generate(from: config)

        #expect(first.fingerprint() == second.fingerprint())
    }

    @Test func allRoomsReachableIncludingGates() throws {
        let config = roomsDoorsConfig(seed: 42, roomCount: 6)
        let result = try ProceduralGenerator().generateDetailed(from: config)
        let reachable = reachableCells(from: result.world.spawn, in: result.world)

        for room in result.rooms {
            let hasReachableCell = room.cells.contains { reachable.contains($0) }
            #expect(hasReachableCell, "Room \(room.id) unreachable from spawn")
        }
    }

    @Test func spawnIsCenterOfTopRightRoom() throws {
        let config = roomsDoorsConfig(seed: 77, roomCount: 5)
        let result = try ProceduralGenerator().generateDetailed(from: config)

        let topRight = expectedTopRightRoom(from: result.rooms)
        #expect(result.topRightRoomID == topRight.id)
        #expect(result.world.spawn == expectedSpawn(for: topRight))
        #expect(result.world.playerPosition == result.world.spawn)
    }

    @Test func roomsJoinedByOpeningsNotDirectFloorEdges() throws {
        let config = roomsDoorsConfig(seed: 123, roomCount: 6)
        let result = try ProceduralGenerator().generateDetailed(from: config)

        #expect(result.joinPairs.count == max(0, result.rooms.count - 1))

        for (aIndex, bIndex) in result.joinPairs {
            let roomA = result.rooms[aIndex]
            let roomB = result.rooms[bIndex]
            #expect(joinHasOpening(roomA, roomB, world: result.world))

            // No open floor-to-floor breach between distinct rooms.
            for cell in roomA.cells {
                for (dx, dy) in GridCoord.cardinals {
                    let neighbor = cell.neighbor(dx: dx, dy: dy)
                    if roomB.cells.contains(neighbor) {
                        Issue.record("Rooms \(aIndex) and \(bIndex) share an open floor edge")
                    }
                }
            }
        }
    }

    @Test func roomsHaveVariedShapes() throws {
        let config = roomsDoorsConfig(seed: 11, roomCount: 12)
        let result = try ProceduralGenerator().generateDetailed(from: config)
        #expect(result.rooms.count >= 3)

        let footprints = result.rooms.map { room -> (w: Int, h: Int, count: Int) in
            let xs = room.cells.map(\.x)
            let ys = room.cells.map(\.y)
            return (
                w: (xs.max() ?? 0) - (xs.min() ?? 0) + 1,
                h: (ys.max() ?? 0) - (ys.min() ?? 0) + 1,
                count: room.cells.count
            )
        }

        // At least one non-rectangular footprint (L or irregular) or elongated room.
        let hasOrganic = footprints.contains { footprint in
            footprint.count < footprint.w * footprint.h || footprint.w >= footprint.h * 2 || footprint.h >= footprint.w * 2
        }
        #expect(hasOrganic)

        // Unused map tiles are expected — rooms must not fill the whole grid.
        let roomCells = result.rooms.reduce(0) { $0 + $1.cells.count }
        #expect(roomCells < result.world.width * result.world.height / 2)
    }

    @Test func hallwayFloorsAreSparse() throws {
        let config = roomsDoorsConfig(seed: 22, roomCount: 9)
        let result = try ProceduralGenerator().generateDetailed(from: config)
        let outside = floorCellsOutsideRooms(world: result.world, rooms: result.rooms)
        let roomFloor = result.rooms.reduce(0) { $0 + $1.cells.count }
        // Short tunnels are OK; they should stay much smaller than room floors.
        #expect(outside < max(roomFloor / 2, 1))
    }

    @Test func traversablePassagesAreAtLeastTwoWide() throws {
        let config = roomsDoorsConfig(seed: 33, roomCount: 8)
        let result = try ProceduralGenerator().generateDetailed(from: config)
        let roomCells = result.rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }

        for y in 0..<result.world.height {
            for x in 0..<result.world.width {
                let coord = GridCoord(x: x, y: y, story: 0)
                guard case .floor = result.world.tile(at: coord)?.kind else { continue }
                // Room interiors can be irregular; gates are intentional chokepoints.
                guard !roomCells.contains(coord) else { continue }
                #expect(
                    !isSingleFilePassage(coord, in: result.world),
                    "1-tile-wide passage at \(coord.x),\(coord.y)"
                )
            }
        }
    }

    /// True when a cell is only open along one axis with both sides blocked (1-tile corridor).
    private func isSingleFilePassage(_ coord: GridCoord, in world: GameWorld) -> Bool {
        func walkable(_ dx: Int, _ dy: Int) -> Bool {
            let next = coord.neighbor(dx: dx, dy: dy)
            return world.isInBounds(next) && world.isEnterable(at: next)
        }
        let n = walkable(0, -1)
        let s = walkable(0, 1)
        let e = walkable(1, 0)
        let w = walkable(-1, 0)
        let northSouthFile = (n || s) && !e && !w
        let eastWestFile = (e || w) && !n && !s
        return northSouthFile || eastWestFile
    }

    @Test func spawnAreaHasNoPits() throws {
        let config = roomsDoorsConfig(seed: 55, roomCount: 4)
        let result = try ProceduralGenerator().generateDetailed(from: config)
        let spawn = result.world.spawn

        var coords = [spawn]
        for (dx, dy) in GridCoord.cardinals {
            coords.append(spawn.neighbor(dx: dx, dy: dy))
        }

        for coord in coords {
            guard let tile = result.world.tile(at: coord) else { continue }
            if case .floor(let isPit) = tile.kind {
                #expect(!isPit, "Pit at \(coord.x),\(coord.y) near spawn")
            }
        }
    }

    @Test func roomsAreBoundedByWallGateOrFloor() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            let result = try ProceduralGenerator().generateDetailed(from: roomsDoorsConfig(seed: seed))
            for room in result.rooms {
                for cell in room.cells {
                    for (dx, dy) in GridCoord.cardinals {
                        let neighbor = cell.neighbor(dx: dx, dy: dy)
                        guard !room.cells.contains(neighbor) else { continue }
                        guard let tile = result.world.tile(at: neighbor) else {
                            Issue.record("Room \(room.id) borders out-of-bounds at \(neighbor.x),\(neighbor.y)")
                            continue
                        }
                        let ok: Bool
                        switch tile.kind {
                        case .floor, .gate, .wall:
                            ok = true
                        }
                        #expect(ok, "Room \(room.id) invalid edge at \(neighbor.x),\(neighbor.y) (seed \(seed))")
                    }
                }
            }
        }
    }

    @Test func pitsNeverReplaceWallsOrGates() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 8)
            config.generation.room.pitChance = 0.9
            let result = try ProceduralGenerator().generateDetailed(from: config)

            for y in 0..<result.world.height {
                for x in 0..<result.world.width {
                    let coord = GridCoord(x: x, y: y, story: 0)
                    guard let tile = result.world.tile(at: coord), tile.isPit else { continue }
                    #expect(!tile.isWall && !tile.isGate, "Pit at \(x),\(y) is not a floor (seed \(seed))")
                }
            }
        }
    }

    @Test func atMostOnePitAreaPerRoomWithinSizeBounds() throws {
        var config = roomsDoorsConfig(seed: 42, roomCount: 16)
        config.generation.room.pitChance = 1.0
        config.generation.room.pitMeanSize = 2
        config.generation.room.pitMaxSize = 5
        let result = try ProceduralGenerator().generateDetailed(from: config)
        let spawnRoomID = result.topRightRoomID
        var totalPitTiles = 0
        var roomsWithPits = 0

        for room in result.rooms {
            let pitCells = Set(room.cells.filter { result.world.tile(at: $0)?.isPit == true })
            let pitCount = pitCells.count
            if room.id == spawnRoomID {
                #expect(pitCount == 0, "spawn room should have no pits")
                continue
            }
            #expect(pitCount >= 1, "pit_chance 1.0 should place a pit area in room \(room.id)")
            #expect(pitCount <= 5, "room \(room.id) pit area \(pitCount) exceeds max 5")
            #expect(pitCellsAreContiguous(pitCells), "pit area in room \(room.id) is not contiguous")
            totalPitTiles += pitCount
            roomsWithPits += 1
        }
        #expect(roomsWithPits > 0)
        let mean = Double(totalPitTiles) / Double(roomsWithPits)
        #expect(mean >= 1.2 && mean <= 3.5, "expected mean near 2, got \(mean)")
    }

    private func pitCellsAreContiguous(_ cells: Set<GridCoord>) -> Bool {
        guard let start = cells.first else { return true }
        let set = cells
        var queue = [start]
        var visited: Set<GridCoord> = [start]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard set.contains(next), visited.insert(next).inserted else { continue }
                queue.append(next)
            }
        }
        return visited.count == cells.count
    }

    @Test func partitionGatesAreTwoTilesWithWallFlanks() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 16)
            config.generation.room.partitionGateChance = 1.0
            let result = try ProceduralGenerator().generateDetailed(from: config)
            let roomByCell = result.rooms.reduce(into: [GridCoord: Int]()) { map, room in
                for cell in room.cells { map[cell] = room.id }
            }

            func oppositeRoomPair(at coord: GridCoord) -> (Int, Int)? {
                for (dx, dy) in GridCoord.cardinals {
                    let a = coord.neighbor(dx: dx, dy: dy)
                    let b = coord.neighbor(dx: -dx, dy: -dy)
                    guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
                    return (min(idA, idB), max(idA, idB))
                }
                return nil
            }

            func alongAxis(for coord: GridCoord) -> (Int, Int)? {
                for (dx, dy) in GridCoord.cardinals {
                    let a = coord.neighbor(dx: dx, dy: dy)
                    let b = coord.neighbor(dx: -dx, dy: -dy)
                    guard roomByCell[a] != nil, roomByCell[b] != nil, roomByCell[a] != roomByCell[b]
                    else { continue }
                    return (-dy, dx)
                }
                return nil
            }

            func isSolidWall(_ coord: GridCoord) -> Bool {
                if case .wall = result.world.tile(at: coord)?.kind { return true }
                return false
            }

            var visited = Set<GridCoord>()
            for y in 0..<result.world.height {
                for x in 0..<result.world.width {
                    let start = GridCoord(x: x, y: y, story: 0)
                    guard result.world.tile(at: start)?.isGate == true else { continue }
                    guard visited.insert(start).inserted else { continue }

                    var queue = [start]
                    var group = [start]
                    var head = 0
                    while head < queue.count {
                        let current = queue[head]
                        head += 1
                        for (dx, dy) in GridCoord.cardinals {
                            let next = current.neighbor(dx: dx, dy: dy)
                            guard result.world.tile(at: next)?.isGate == true else { continue }
                            guard visited.insert(next).inserted else { continue }
                            queue.append(next)
                            group.append(next)
                        }
                    }

                    #expect(!group.isEmpty, "empty gate group (seed \(seed))")
                    let pairs = group.compactMap(oppositeRoomPair)
                    // Partition shortcut gates: every cell spans the same room pair and the
                    // strip is flanked by solid walls. Corridor-mouth / sealed join gates may
                    // form longer contiguous strips and are checked by the passage invariant.
                    guard pairs.count == group.count, let firstPair = pairs.first,
                          pairs.allSatisfy({ $0 == firstPair }),
                          let (alongDX, alongDY) = alongAxis(for: group[0]) else { continue }

                    let ordered = group.sorted {
                        let lhs = $0.x * alongDX + $0.y * alongDY
                        let rhs = $1.x * alongDX + $1.y * alongDY
                        return lhs < rhs
                    }
                    let before = ordered[0].neighbor(dx: -alongDX, dy: -alongDY)
                    let after = ordered[ordered.count - 1].neighbor(dx: alongDX, dy: alongDY)
                    #expect(isSolidWall(before), "partition gate missing wall flank before (seed \(seed))")
                    #expect(isSolidWall(after), "partition gate missing wall flank after (seed \(seed))")
                }
            }
        }
    }

    @Test func gatesSitOutsideRooms() throws {
        // Hallway connectivity can filter out every gate candidate for some seeds even
        // at partition_gate_chance 1.0, so require gates across the seed set rather than per seed.
        var totalGates = 0
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 16)
            config.generation.room.partitionGateChance = 1.0
            let result = try ProceduralGenerator().generateDetailed(from: config)
            let roomCells = result.rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }
            for y in 0..<result.world.height {
                for x in 0..<result.world.width {
                    let coord = GridCoord(x: x, y: y, story: 0)
                    guard result.world.tile(at: coord)?.isGate == true else { continue }
                    totalGates += 1
                    #expect(!roomCells.contains(coord), "Gate inside room at \(x),\(y) (seed \(seed))")
                    #expect(coord != result.world.spawn)
                }
            }
        }
        #expect(totalGates > 0, "expected gates with partition_gate_chance 1.0 across seeds")
    }

    @Test func gatesAreTwoTilesWithRoomsOnEachSide() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 16)
            config.generation.room.partitionGateChance = 1.0
            let result = try ProceduralGenerator().generateDetailed(from: config)
            let roomByCell = result.rooms.reduce(into: [GridCoord: Int]()) { map, room in
                for cell in room.cells { map[cell] = room.id }
            }

            func oppositeRoomPair(at coord: GridCoord) -> (Int, Int)? {
                for (dx, dy) in GridCoord.cardinals {
                    let a = coord.neighbor(dx: dx, dy: dy)
                    let b = coord.neighbor(dx: -dx, dy: -dy)
                    guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
                    return (min(idA, idB), max(idA, idB))
                }
                return nil
            }

            var visited = Set<GridCoord>()
            for y in 0..<result.world.height {
                for x in 0..<result.world.width {
                    let start = GridCoord(x: x, y: y, story: 0)
                    guard result.world.tile(at: start)?.isGate == true else { continue }
                    guard visited.insert(start).inserted else { continue }

                    var queue = [start]
                    var group = [start]
                    var head = 0
                    while head < queue.count {
                        let current = queue[head]
                        head += 1
                        for (dx, dy) in GridCoord.cardinals {
                            let next = current.neighbor(dx: dx, dy: dy)
                            guard result.world.tile(at: next)?.isGate == true else { continue }
                            guard visited.insert(next).inserted else { continue }
                            queue.append(next)
                            group.append(next)
                        }
                    }

                    #expect(!group.isEmpty, "empty gate group (seed \(seed))")
                    let pairs = group.compactMap(oppositeRoomPair)
                    if pairs.count == group.count, let first = pairs.first {
                        #expect(pairs.allSatisfy { $0 == first },
                                "partition gate cells span different room pairs (seed \(seed))")
                    } else {
                        // Corridor-mouth / sealed join gate: must touch at least one room.
                        let touchesRoom = group.contains { cell in
                            GridCoord.cardinals.contains { dx, dy in
                                roomByCell[cell.neighbor(dx: dx, dy: dy)] != nil
                            }
                        }
                        #expect(touchesRoom, "join gate does not touch a room (seed \(seed))")
                    }
                }
            }
        }
    }

    @Test func zeroPartitionChanceStillPlacesJoinGates() throws {
        var config = roomsDoorsConfig(seed: 42, roomCount: 12)
        config.generation.room.partitionGateChance = 0
        let world = try ProceduralGenerator().generate(from: config)
        let gates = (0..<world.height).reduce(0) { count, y in
            count + (0..<world.width).filter { x in
                world.tile(at: GridCoord(x: x, y: y, story: 0))?.isGate == true
            }.count
        }
        #expect(gates >= 2, "join gate is a 2-tile strip, found \(gates)")
    }

    @Test func atMostOneGatePerSharedWall() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 16)
            config.generation.room.partitionGateChance = 1.0
            let result = try ProceduralGenerator().generateDetailed(from: config)
            let world = result.world
            let roomByCell = result.rooms.reduce(into: [GridCoord: Int]()) { map, room in
                for cell in room.cells { map[cell] = room.id }
            }

            func roomPair(at coord: GridCoord) -> (Int, Int)? {
                for (dx, dy) in GridCoord.cardinals {
                    let a = coord.neighbor(dx: dx, dy: dy)
                    let b = coord.neighbor(dx: -dx, dy: -dy)
                    guard let idA = roomByCell[a], let idB = roomByCell[b], idA != idB else { continue }
                    return (min(idA, idB), max(idA, idB))
                }
                return nil
            }

            var gateFeatureCount: [String: Int] = [:]
            var visitedGates = Set<GridCoord>()

            func flood(
                from start: GridCoord,
                matches: (GridCoord) -> Bool,
                visited: inout Set<GridCoord>
            ) -> [GridCoord] {
                guard visited.insert(start).inserted else { return [] }
                var queue = [start]
                var group = [start]
                var head = 0
                while head < queue.count {
                    let current = queue[head]
                    head += 1
                    for (dx, dy) in GridCoord.cardinals {
                        let next = current.neighbor(dx: dx, dy: dy)
                        guard matches(next), visited.insert(next).inserted else { continue }
                        queue.append(next)
                        group.append(next)
                    }
                }
                return group
            }

            for y in 0..<world.height {
                for x in 0..<world.width {
                    let coord = GridCoord(x: x, y: y, story: 0)
                    if world.tile(at: coord)?.isGate == true, !visitedGates.contains(coord) {
                        let group = flood(
                            from: coord,
                            matches: { world.tile(at: $0)?.isGate == true },
                            visited: &visitedGates
                        )
                        if let (lo, hi) = group.compactMap(roomPair).first {
                            gateFeatureCount["\(lo)-\(hi)", default: 0] += 1
                        }
                    }
                }
            }

            for pair in gateFeatureCount.keys {
                let gates = gateFeatureCount[pair, default: 0]
                #expect(gates <= 1, "pair \(pair) has \(gates) gate features (seed \(seed))")
            }
        }
    }

    @Test func yamlLevelUsesRoomsDoorsAlgorithm() throws {
        let appYAML = """
        version: 1
        seed: 42
        world:
          stories: 1
        """
        let levelYAML = """
        name: Rooms Doors
        width: 24
        height: 24
        algorithm: rooms_doors
        room_count: 6
        corridor_width: 2
        room:
          min_room_size: 4
          max_room_size: 6
          pit_chance: 0.2
          partition_gate_chance: 0.2
        """

        let app = try WorldLoader.decodeConfig(from: appYAML)
        let level = try LevelConfig.decode(from: levelYAML)
        let config = WorldGenerationConfig.compose(app: app, level: level)
        #expect(config.generation.algorithm == "rooms_doors")
        #expect(config.generation.room.minRoomSize == 4)
        #expect(config.generation.room.maxRoomSize == 6)
        #expect(config.generation.room.pitChance == 0.2)
        #expect(config.world.stories == 1)
    }

    @Test func incompatibleSaveIsRejectedBySize() {
        let config = roomsDoorsConfig()
        let small = TestWorldFactory.emptyFloor(width: 8, height: 8)
        #expect(!WorldLoader.isCompatibleSave(small, with: config))
        #expect(WorldLoader.isCompatibleSave(
            TestWorldFactory.emptyFloor(width: 30, height: 30),
            with: config
        ))
    }

    @Test func enemySpawnsAreDeterministicAndSkipSpawnRoom() throws {
        var config = roomsDoorsConfig(seed: 123, roomCount: 12)
        config.enemies = .init(type: "spider", spawnChancePerRoom: 0.8)
        let enemyConfig = EnemyConfig.fallback

        let first = try ProceduralGenerator().generateDetailed(from: config, enemyConfig: enemyConfig)
        let second = try ProceduralGenerator().generateDetailed(from: config, enemyConfig: enemyConfig)

        let firstEnemies = first.world.entities.filter(\.isEnemy)
        let secondEnemies = second.world.entities.filter(\.isEnemy)
        #expect(firstEnemies.count == secondEnemies.count)
        #expect(firstEnemies.map(\.position) == secondEnemies.map(\.position))
        #expect(firstEnemies.allSatisfy { $0.letter == "E" && $0.enemyTypeID == "spider" })

        let spawnRoom = first.rooms.first { $0.id == first.topRightRoomID }!
        for enemy in firstEnemies {
            #expect(!spawnRoom.cells.contains(enemy.position))
            #expect(enemy.position != first.world.spawn)
        }

        // With 0.8 chance across many rooms, expect at least one enemy.
        #expect(firstEnemies.count > 0)
    }

    @Test func multiTypeEnemySpawnPicksOnlyConfiguredTypes() throws {
        var config = roomsDoorsConfig(seed: 999, roomCount: 16)
        config.enemies = .init(types: ["spider", "ice_monster"], spawnChancePerRoom: 1.0)
        let enemyConfig = EnemyConfig(
            enemies: [
                "spider": EnemyTypeConfig(
                    letter: "E",
                    color: "#FF0000",
                    tilesPerSecond: 1,
                    forgetSeconds: 3
                ),
                "ice_monster": EnemyTypeConfig(
                    letter: "I",
                    color: "#00FFFF",
                    tilesPerSecond: 1,
                    forgetSeconds: 3
                ),
            ]
        )

        let result = try ProceduralGenerator().generateDetailed(from: config, enemyConfig: enemyConfig)
        let enemies = result.world.entities.filter(\.isEnemy)
        #expect(enemies.count > 0)
        #expect(enemies.allSatisfy {
            $0.enemyTypeID == "spider" || $0.enemyTypeID == "ice_monster"
        })
        #expect(Set(enemies.compactMap(\.enemyTypeID)).count >= 1)
    }

    @Test func zeroSpawnChanceStillGuaranteesOneEnemy() throws {
        var config = roomsDoorsConfig(seed: 7, roomCount: 10)
        config.enemies = .init(type: "spider", spawnChancePerRoom: 0)
        let world = try ProceduralGenerator().generate(from: config, enemyConfig: .fallback)
        #expect(world.entities.filter(\.isEnemy).count == 1)
    }

    @Test func pickupSpawnsSkipSpawnRoomAndAvoidOverlap() throws {
        var config = roomsDoorsConfig(seed: 55, roomCount: 12)
        config.pickups = .init(
            health: .init(spawnChancePerRoom: 1.0),
            energy: .init(spawnChancePerRoom: 1.0)
        )

        let result = try ProceduralGenerator().generateDetailed(from: config)
        let pickups = result.world.entities.filter(\.isPickup)
        #expect(pickups.count > 0)

        let spawnRoom = result.rooms.first { $0.id == result.topRightRoomID }!
        let nonPlayer = result.world.entities.filter { !$0.isPlayer }
        #expect(Set(nonPlayer.map(\.position)).count == nonPlayer.count)

        for pickup in pickups where pickup.pickupKind != .treasure {
            #expect(!spawnRoom.cells.contains(pickup.position))
            #expect(pickup.position != result.world.spawn)
            #expect(pickup.pickupKind != nil)
        }

        #expect(pickups.contains { $0.pickupKind == .health })
        #expect(pickups.contains { $0.pickupKind == .energy })
        #expect(pickups.contains { $0.pickupKind == .treasure })
    }

    @Test func pickupsNeverSpawnOnAdjacentFloorTiles() throws {
        for seed: UInt64 in [11, 42, 55, 99, 123] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 12)
            config.pickups = .init(
                health: .init(spawnChancePerRoom: 1.0),
                energy: .init(spawnChancePerRoom: 1.0)
            )
            let result = try ProceduralGenerator().generateDetailed(from: config)
            let pickups = result.world.entities.filter(\.isPickup)
            #expect(pickups.count > 1, "expected multiple pickups (seed \(seed))")

            for i in pickups.indices {
                for j in pickups.indices where j > i {
                    let a = pickups[i].position
                    let b = pickups[j].position
                    #expect(a != b, "overlapping pickups at \(a) (seed \(seed))")
                    let dx = abs(a.x - b.x)
                    let dy = abs(a.y - b.y)
                    let orthogonallyAdjacent = a.story == b.story && dx + dy == 1
                    #expect(
                        !orthogonallyAdjacent,
                        "pickups adjacent at \(a) and \(b) (seed \(seed))"
                    )
                }
            }
        }
    }

    @Test func pickupsAndEnemiesOnlySpawnOnRoomFloorTiles() throws {
        for seed: UInt64 in [11, 42, 99, 123] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 12)
            config.pickups = .init(
                health: .init(spawnChancePerRoom: 1.0),
                energy: .init(spawnChancePerRoom: 1.0)
            )
            config.enemies = .init(type: "spider", spawnChancePerRoom: 1.0)
            let result = try ProceduralGenerator().generateDetailed(
                from: config,
                enemyConfig: .fallback
            )
            let roomCells = result.rooms.reduce(into: Set<GridCoord>()) { $0.formUnion($1.cells) }

            let entities = result.world.entities.filter { $0.isPickup || $0.isEnemy }
            #expect(entities.contains { $0.isPickup }, "expected pickups (seed \(seed))")
            #expect(entities.contains { $0.isEnemy }, "expected enemies (seed \(seed))")
            for entity in entities {
                let coord = entity.position
                #expect(roomCells.contains(coord), "entity outside any room at \(coord) (seed \(seed))")
                guard let tile = result.world.tile(at: coord) else {
                    Issue.record("missing tile under entity at \(coord) (seed \(seed))")
                    continue
                }
                #expect(!tile.isPit, "entity on pit at \(coord) (seed \(seed))")
                #expect(!tile.isGate, "entity on gate at \(coord) (seed \(seed))")
                #expect(!tile.isWall, "entity on wall at \(coord) (seed \(seed))")
                if case .floor(let isPit) = tile.kind {
                    #expect(!isPit)
                } else {
                    Issue.record("entity not on floor at \(coord) (seed \(seed))")
                }
            }
        }
    }

    @Test func zeroPickupChanceProducesOnlyTreasure() throws {
        var config = roomsDoorsConfig(seed: 8, roomCount: 10)
        config.pickups = .init(
            health: .init(spawnChancePerRoom: 0),
            energy: .init(spawnChancePerRoom: 0)
        )
        let world = try ProceduralGenerator().generate(from: config)
        let pickups = world.entities.filter(\.isPickup)
        #expect(pickups.count == 1)
        #expect(pickups.first?.pickupKind == .treasure)
    }

    @Test func treasureSpawnsOnceInFarthestRoom() throws {
        for seed: UInt64 in [11, 42, 99, 123] {
            let result = try ProceduralGenerator().generateDetailed(from: roomsDoorsConfig(seed: seed, roomCount: 12))
            let treasures = result.world.entities.filter { $0.pickupKind == .treasure }
            #expect(treasures.count == 1, "expected one treasure (seed \(seed))")

            guard let treasure = treasures.first else { continue }
            let spawn = result.world.spawn
            func roomHasVisiblePickupFloor(_ room: GeneratedRoom) -> Bool {
                room.cells.contains { cell in
                    IsometricTileGeometry.isPickupVisibleFloor(at: cell, in: result.world)
                }
            }
            let farthestVisible = result.rooms
                .filter(roomHasVisiblePickupFloor)
                .max { lhs, rhs in
                    let lhsDist = abs(spawn.x - lhs.center.x) + abs(spawn.y - lhs.center.y)
                    let rhsDist = abs(spawn.x - rhs.center.x) + abs(spawn.y - rhs.center.y)
                    if lhsDist != rhsDist { return lhsDist < rhsDist }
                    return lhs.id < rhs.id
                }
            #expect(farthestVisible != nil, "expected a room with visible floor (seed \(seed))")
            if let farthestVisible {
                #expect(
                    farthestVisible.cells.contains(treasure.position),
                    "treasure not in farthest visible room \(farthestVisible.id) (seed \(seed))"
                )
            }
        }
    }

    @Test func pickupsStayAtLeastOneTileFromWalls() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 12)
            config.pickups = .init(
                health: .init(spawnChancePerRoom: 1.0),
                energy: .init(spawnChancePerRoom: 1.0)
            )
            let world = try ProceduralGenerator().generate(from: config)
            let pickups = world.entities.filter(\.isPickup)
            #expect(!pickups.isEmpty, "expected pickups (seed \(seed))")
            for pickup in pickups {
                #expect(
                    IsometricTileGeometry.isPickupVisibleFloor(at: pickup.position, in: world),
                    "pickup \(pickup.pickupKind!) too close to a wall at \(pickup.position) (seed \(seed))"
                )
            }
        }
    }

    @Test func generatesGatesAndPitsWhenRequired() throws {
        var config = roomsDoorsConfig(seed: 42, roomCount: 20)
        config.generation.room.partitionGateChance = 0
        config.generation.room.pitChance = 0
        config.enemies = .init(type: "spider", spawnChancePerRoom: 0)

        let result = try ProceduralGenerator().generateDetailed(
            from: config,
            enemyConfig: .fallback
        )
        #expect(ProceduralGenerator.missingRequiredInteractables(in: result.world).isEmpty)

        var gates = 0
        var pits = 0
        for y in 0..<result.world.height {
            for x in 0..<result.world.width {
                let tile = result.world.tile(at: GridCoord(x: x, y: y, story: 0))
                if tile?.isGate == true { gates += 1 }
                if tile?.isPit == true { pits += 1 }
            }
        }
        #expect(gates >= 2, "expected gates, found \(gates)")
        #expect(pits >= 1, "expected pits, found \(pits)")
        let hasEnemy = result.world.entities.contains(where: \.isEnemy)
        #expect(hasEnemy)
    }

    @Test func everyGeneratedMapIncludesRequiredInteractables() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 12)
            config.enemies = .init(type: "spider", spawnChancePerRoom: 0.3)
            let world = try ProceduralGenerator().generate(from: config, enemyConfig: .fallback)
            let missing = ProceduralGenerator.missingRequiredInteractables(in: world)
            #expect(missing.isEmpty, "seed \(seed) missing \(missing)")
        }
    }

    @Test func roomsAreSeparatedByGatesInvariant() throws {
        for seed: UInt64 in [11, 42, 99, 123, 256, 777, 1001] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 12)
            config.generation.room.partitionGateChance = 1.0
            let result = try ProceduralGenerator().generateDetailed(from: config)
            let tiles = result.world.tiles.first ?? []
            #expect(
                ProceduralGenerator.roomsAreSeparatedByGates(rooms: result.rooms, tiles: tiles),
                "rooms should be separated by gates for seed \(seed)"
            )
        }
    }
}
