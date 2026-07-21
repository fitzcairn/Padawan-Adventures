import Testing
@testable import Padawan_Adventures

struct ProceduralGeneratorTests {
    private func roomsDoorsConfig(seed: UInt64 = 99, roomCount: Int = 6) -> WorldSeedConfig {
        WorldSeedConfig(
            version: 1,
            seed: seed,
            world: .init(width: 30, height: 30, stories: 1),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: roomCount,
                corridorWidth: 2,
                minRoomSize: 4,
                maxRoomSize: 10,
                pitChance: 0.1,
                wallDestructibleChance: 0.3,
                doorCount: 2
            ),
            player: .init(letter: "P", spawn: .init(x: 1, y: 1, story: 0)),
            extensions: nil
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

    private func joinHasDoor(
        _ roomA: GeneratedRoom,
        _ roomB: GeneratedRoom,
        world: GameWorld
    ) -> Bool {
        func boundaryDoor(of room: GeneratedRoom) -> Bool {
            for cell in room.cells {
                for (dx, dy) in GridCoord.cardinals {
                    let neighbor = cell.neighbor(dx: dx, dy: dy)
                    guard !room.cells.contains(neighbor) else { continue }
                    if case .wall(_, true) = world.tile(at: neighbor)?.kind {
                        return true
                    }
                }
            }
            return false
        }
        // Adjacent joins share a wall door; tunnel joins put a door on each room ring.
        return boundaryDoor(of: roomA) && boundaryDoor(of: roomB)
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

    @Test func allRoomsReachableViaDoors() throws {
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

    @Test func roomsJoinedByDoorsNotOpenGaps() throws {
        let config = roomsDoorsConfig(seed: 123, roomCount: 6)
        let result = try ProceduralGenerator().generateDetailed(from: config)

        #expect(result.joinPairs.count == max(0, result.rooms.count - 1))

        for (aIndex, bIndex) in result.joinPairs {
            let roomA = result.rooms[aIndex]
            let roomB = result.rooms[bIndex]
            #expect(joinHasDoor(roomA, roomB, world: result.world))

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
                guard result.world.isEnterable(at: coord) else { continue }
                // Room interiors can be irregular; enforce width on hallways/doors only.
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

    @Test func roomsAreFullyEnclosedByWallsOrDoors() throws {
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
                        #expect(
                            tile.isWall,
                            "Room \(room.id) open edge at \(neighbor.x),\(neighbor.y) (seed \(seed))"
                        )
                    }
                }
            }
        }
    }

    @Test func pitsAlwaysTouchAWallAndNeverReplaceWalls() throws {
        for seed: UInt64 in [11, 42, 99, 123, 777] {
            var config = roomsDoorsConfig(seed: seed, roomCount: 8)
            config.generation.pitChance = 0.9
            let result = try ProceduralGenerator().generateDetailed(from: config)

            for y in 0..<result.world.height {
                for x in 0..<result.world.width {
                    let coord = GridCoord(x: x, y: y, story: 0)
                    guard let tile = result.world.tile(at: coord), tile.isPit else { continue }
                    #expect(
                        !tile.isWall,
                        "Pit replaced a wall at \(x),\(y) (seed \(seed))"
                    )

                    let touchesWall = GridCoord.cardinals.contains { dx, dy in
                        let neighbor = coord.neighbor(dx: dx, dy: dy)
                        return result.world.tile(at: neighbor)?.isWall == true
                    }
                    #expect(touchesWall, "Pit at \(x),\(y) has no wall neighbor (seed \(seed))")
                }
            }
        }
    }

    @Test func yamlSeedUsesRoomsDoorsAlgorithm() throws {
        let yaml = """
        version: 1
        seed: 42
        world:
          width: 24
          height: 24
          stories: 1
        generation:
          algorithm: rooms_doors
          room_count: 6
          corridor_width: 2
          min_room_size: 4
          max_room_size: 6
          pit_chance: 0.05
          wall_destructible_chance: 0.2
          door_count: 4
        player:
          letter: P
        extensions: {}
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.generation.algorithm == "rooms_doors")
        #expect(config.generation.minRoomSize == 4)
        #expect(config.generation.maxRoomSize == 6)
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
        config.enemies = .init(type: "grunt", spawnChancePerRoom: 0.8)
        let enemyConfig = EnemyConfig.fallback

        let first = try ProceduralGenerator().generateDetailed(from: config, enemyConfig: enemyConfig)
        let second = try ProceduralGenerator().generateDetailed(from: config, enemyConfig: enemyConfig)

        let firstEnemies = first.world.entities.filter(\.isEnemy)
        let secondEnemies = second.world.entities.filter(\.isEnemy)
        #expect(firstEnemies.count == secondEnemies.count)
        #expect(firstEnemies.map(\.position) == secondEnemies.map(\.position))
        #expect(firstEnemies.allSatisfy { $0.letter == "E" && $0.enemyTypeID == "grunt" })

        let spawnRoom = first.rooms.first { $0.id == first.topRightRoomID }!
        for enemy in firstEnemies {
            #expect(!spawnRoom.cells.contains(enemy.position))
            #expect(enemy.position != first.world.spawn)
        }

        // With 0.8 chance across many rooms, expect at least one enemy.
        #expect(firstEnemies.count > 0)
    }

    @Test func zeroSpawnChanceProducesNoEnemies() throws {
        var config = roomsDoorsConfig(seed: 7, roomCount: 10)
        config.enemies = .init(type: "grunt", spawnChancePerRoom: 0)
        let world = try ProceduralGenerator().generate(from: config, enemyConfig: .fallback)
        #expect(world.entities.filter(\.isEnemy).isEmpty)
    }

    @Test func pickupSpawnsSkipSpawnRoomAndAvoidOverlap() throws {
        var config = roomsDoorsConfig(seed: 55, roomCount: 12)
        config.pickups = .init(
            health: .init(spawnChancePerRoom: 1.0),
            energy: .init(spawnChancePerRoom: 1.0),
            treasure: .init(spawnChancePerRoom: 1.0)
        )

        let result = try ProceduralGenerator().generateDetailed(from: config)
        let pickups = result.world.entities.filter(\.isPickup)
        #expect(pickups.count > 0)

        let spawnRoom = result.rooms.first { $0.id == result.topRightRoomID }!
        let nonPlayer = result.world.entities.filter { !$0.isPlayer }
        #expect(Set(nonPlayer.map(\.position)).count == nonPlayer.count)

        for pickup in pickups {
            #expect(!spawnRoom.cells.contains(pickup.position))
            #expect(pickup.position != result.world.spawn)
            #expect(pickup.pickupKind != nil)
        }

        #expect(pickups.contains { $0.pickupKind == .health })
        #expect(pickups.contains { $0.pickupKind == .energy })
        #expect(pickups.contains { $0.pickupKind == .treasure })
    }

    @Test func zeroPickupChanceProducesNoPickups() throws {
        var config = roomsDoorsConfig(seed: 8, roomCount: 10)
        config.pickups = .init(
            health: .init(spawnChancePerRoom: 0),
            energy: .init(spawnChancePerRoom: 0),
            treasure: .init(spawnChancePerRoom: 0)
        )
        let world = try ProceduralGenerator().generate(from: config)
        #expect(world.entities.filter(\.isPickup).isEmpty)
    }
}
