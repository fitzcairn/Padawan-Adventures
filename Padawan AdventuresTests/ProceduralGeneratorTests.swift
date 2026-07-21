import Testing
@testable import Padawan_Adventures

struct ProceduralGeneratorTests {
    private func roomsDoorsConfig(seed: UInt64 = 99, roomCount: Int = 6) -> WorldSeedConfig {
        WorldSeedConfig(
            version: 1,
            seed: seed,
            world: .init(width: 24, height: 24, stories: 2),
            generation: .init(
                algorithm: "rooms_doors",
                roomCount: roomCount,
                corridorWidth: 1,
                minRoomSize: 5,
                maxRoomSize: 8,
                pitChance: 0.1,
                wallDestructibleChance: 0.3,
                rampCount: 1,
                ladderCount: 1,
                slideCount: 1,
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
        for cell in roomA.cells {
            for (dx, dy) in GridCoord.cardinals {
                let neighbor = cell.neighbor(dx: dx, dy: dy)
                guard !roomA.cells.contains(neighbor) else { continue }
                if case .wall(_, true, _) = world.tile(at: neighbor)?.kind {
                    return true
                }
            }
        }
        for cell in roomB.cells {
            for (dx, dy) in GridCoord.cardinals {
                let neighbor = cell.neighbor(dx: dx, dy: dy)
                guard !roomB.cells.contains(neighbor) else { continue }
                if case .wall(_, true, _) = world.tile(at: neighbor)?.kind {
                    return true
                }
            }
        }
        return false
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
        }
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

    @Test func yamlSeedUsesRoomsDoorsAlgorithm() throws {
        let yaml = """
        version: 1
        seed: 42
        world:
          width: 24
          height: 24
          stories: 2
        generation:
          algorithm: rooms_doors
          room_count: 6
          corridor_width: 1
          min_room_size: 4
          max_room_size: 6
          pit_chance: 0.05
          wall_destructible_chance: 0.2
          ramp_count: 2
          ladder_count: 2
          slide_count: 1
          door_count: 4
        player:
          letter: P
        extensions: {}
        """

        let config = try WorldLoader.decodeConfig(from: yaml)
        #expect(config.generation.algorithm == "rooms_doors")
        #expect(config.generation.minRoomSize == 4)
        #expect(config.generation.maxRoomSize == 6)
    }
}
