import Foundation

struct ProceduralGenerator: Sendable {
    func generate(from config: WorldSeedConfig) throws -> GameWorld {
        try config.validate()

        var rng = SeededGenerator(seed: config.seed)
        let width = config.world.width
        let height = config.world.height
        let stories = config.world.stories

        var tiles = Array(
            repeating: Array(
                repeating: Array(repeating: Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: false)), count: width),
                count: height
            ),
            count: stories
        )

        for story in 0..<stories {
            carveRooms(into: &tiles[story], width: width, height: height, roomCount: config.generation.roomCount, rng: &rng)
            sprinklePits(into: &tiles[story], chance: config.generation.pitChance, rng: &rng)
            markDestructibleWalls(in: &tiles[story], chance: config.generation.wallDestructibleChance, rng: &rng)
        }

        placeDoors(in: &tiles, count: config.generation.doorCount, rng: &rng)
        placeLadders(in: &tiles, count: config.generation.ladderCount, rng: &rng)
        placeRamps(in: &tiles, count: config.generation.rampCount, rng: &rng)
        placeSlides(in: &tiles, count: config.generation.slideCount, rng: &rng)

        let spawn = resolveSpawn(config: config, tiles: tiles, width: width, height: height, stories: stories)
        let letter = config.player.letter.first ?? "P"
        let player = GameEntity(letter: letter, position: spawn, isPlayer: true)

        return GameWorld(
            width: width,
            height: height,
            storyCount: stories,
            tiles: tiles,
            entities: [player],
            spawn: spawn
        )
    }

    private struct Room: Equatable {
        var x: Int
        var y: Int
        var width: Int
        var height: Int

        var center: (x: Int, y: Int) {
            (x + width / 2, y + height / 2)
        }
    }

    private func carveRooms(
        into story: inout [[Tile]],
        width: Int,
        height: Int,
        roomCount: Int,
        rng: inout SeededGenerator
    ) {
        var rooms: [Room] = []

        for _ in 0..<roomCount {
            let roomWidth = rng.nextInt(upperBound: max(1, width / 4)) + 4
            let roomHeight = rng.nextInt(upperBound: max(1, height / 4)) + 4
            let x = rng.nextInt(upperBound: max(1, width - roomWidth - 2)) + 1
            let y = rng.nextInt(upperBound: max(1, height - roomHeight - 2)) + 1
            let room = Room(x: x, y: y, width: roomWidth, height: roomHeight)
            rooms.append(room)

            for row in y..<min(y + roomHeight, height - 1) {
                for col in x..<min(x + roomWidth, width - 1) {
                    story[row][col] = Tile(kind: .floor(isPit: false))
                }
            }
        }

        for index in 1..<rooms.count {
            connect(
                from: rooms[index - 1].center,
                to: rooms[index].center,
                in: &story,
                width: width,
                height: height
            )
        }
    }

    private func connect(
        from start: (x: Int, y: Int),
        to end: (x: Int, y: Int),
        in story: inout [[Tile]],
        width: Int,
        height: Int
    ) {
        var x = start.x
        var y = start.y

        while x != end.x {
            if x >= 0, x < width, y >= 0, y < height {
                story[y][x] = Tile(kind: .floor(isPit: false))
            }
            x += x < end.x ? 1 : -1
        }

        while y != end.y {
            if x >= 0, x < width, y >= 0, y < height {
                story[y][x] = Tile(kind: .floor(isPit: false))
            }
            y += y < end.y ? 1 : -1
        }
    }

    private func sprinklePits(into story: inout [[Tile]], chance: Double, rng: inout SeededGenerator) {
        for y in 0..<story.count {
            for x in 0..<story[y].count {
                if case .floor = story[y][x].kind, rng.nextBool(probability: chance) {
                    story[y][x] = Tile(kind: .floor(isPit: true))
                }
            }
        }
    }

    private func markDestructibleWalls(
        in story: inout [[Tile]],
        chance: Double,
        rng: inout SeededGenerator
    ) {
        for y in 0..<story.count {
            for x in 0..<story[y].count {
                if case .wall = story[y][x].kind, rng.nextBool(probability: chance) {
                    story[y][x] = Tile(kind: .wall(destructible: true, hasDoor: false, hasLadder: false))
                }
            }
        }
    }

    private func placeDoors(in tiles: inout [[[Tile]]], count: Int, rng: inout SeededGenerator) {
        var placed = 0
        var attempts = 0
        while placed < count, attempts < count * 50 {
            attempts += 1
            let story = rng.nextInt(upperBound: tiles.count)
            let y = rng.nextInt(upperBound: tiles[story].count)
            let x = rng.nextInt(upperBound: tiles[story][y].count)
            let coord = GridCoord(x: x, y: y, story: story)

            guard case .wall(let destructible, false, false) = tiles[story][y][x].kind else { continue }
            guard adjacentFloorCount(at: coord, tiles: tiles) >= 2 else { continue }

            tiles[story][y][x] = Tile(kind: .wall(destructible: destructible, hasDoor: true, hasLadder: false))
            placed += 1
        }
    }

    private func placeLadders(in tiles: inout [[[Tile]]], count: Int, rng: inout SeededGenerator) {
        var placed = 0
        var attempts = 0
        while placed < count, attempts < count * 50 {
            attempts += 1
            let x = rng.nextInt(upperBound: tiles[0][0].count)
            let y = rng.nextInt(upperBound: tiles[0].count)

            for story in 0..<(tiles.count - 1) {
                guard case .wall(let destructible, let door, false) = tiles[story][y][x].kind else { continue }
                guard case .wall = tiles[story + 1][y][x].kind else { continue }
                guard adjacentFloorCount(at: GridCoord(x: x, y: y, story: story), tiles: tiles) >= 1 else { continue }

                tiles[story][y][x] = Tile(kind: .wall(destructible: destructible, hasDoor: door, hasLadder: true))
                tiles[story + 1][y][x] = Tile(kind: .wall(destructible: false, hasDoor: false, hasLadder: true))
                placed += 1
                break
            }
        }
    }

    private func placeRamps(in tiles: inout [[[Tile]]], count: Int, rng: inout SeededGenerator) {
        var placed = 0
        var attempts = 0
        while placed < count, attempts < count * 50 {
            attempts += 1
            let lowerStory = 0
            let upperStory = 1
            let horizontal = rng.nextBool(probability: 0.5)
            let x = rng.nextInt(upperBound: tiles[lowerStory][0].count - (horizontal ? 2 : 1))
            let y = rng.nextInt(upperBound: tiles[lowerStory].count - (horizontal ? 1 : 2))

            let a = GridCoord(x: x, y: y, story: lowerStory)
            let b = horizontal
                ? GridCoord(x: x + 1, y: y, story: lowerStory)
                : GridCoord(x: x, y: y + 1, story: lowerStory)

            guard isFloor(tiles[lowerStory][a.y][a.x]), isFloor(tiles[lowerStory][b.y][b.x]) else { continue }
            guard isFloor(tiles[upperStory][a.y][a.x]), isFloor(tiles[upperStory][b.y][b.x]) else { continue }

            tiles[lowerStory][a.y][a.x] = Tile(kind: .ramp(partner: b, otherStory: upperStory))
            tiles[lowerStory][b.y][b.x] = Tile(kind: .ramp(partner: a, otherStory: upperStory))
            placed += 1
        }
    }

    private func placeSlides(in tiles: inout [[[Tile]]], count: Int, rng: inout SeededGenerator) {
        var placed = 0
        var attempts = 0
        let upperStory = 1
        let lowerStory = 0

        while placed < count, attempts < count * 50 {
            attempts += 1
            let horizontal = rng.nextBool(probability: 0.5)
            let x = rng.nextInt(upperBound: tiles[upperStory][0].count - (horizontal ? 2 : 1))
            let y = rng.nextInt(upperBound: tiles[upperStory].count - (horizontal ? 1 : 2))

            let a = GridCoord(x: x, y: y, story: upperStory)
            let b = horizontal
                ? GridCoord(x: x + 1, y: y, story: upperStory)
                : GridCoord(x: x, y: y + 1, story: upperStory)

            guard isFloor(tiles[upperStory][a.y][a.x]), isFloor(tiles[upperStory][b.y][b.x]) else { continue }
            guard isFloor(tiles[lowerStory][a.y][a.x]), isFloor(tiles[lowerStory][b.y][b.x]) else { continue }

            tiles[upperStory][a.y][a.x] = Tile(kind: .slide(partner: b, lowerStory: lowerStory))
            tiles[upperStory][b.y][b.x] = Tile(kind: .slide(partner: a, lowerStory: lowerStory))
            placed += 1
        }
    }

    private func isFloor(_ tile: Tile) -> Bool {
        if case .floor = tile.kind { return true }
        return false
    }

    private func adjacentFloorCount(at coord: GridCoord, tiles: [[[Tile]]]) -> Int {
        var count = 0
        for (dx, dy) in GridCoord.cardinals {
            let neighbor = coord.neighbor(dx: dx, dy: dy)
            guard neighbor.story >= 0, neighbor.story < tiles.count else { continue }
            guard neighbor.y >= 0, neighbor.y < tiles[neighbor.story].count else { continue }
            guard neighbor.x >= 0, neighbor.x < tiles[neighbor.story][neighbor.y].count else { continue }
            if isFloor(tiles[neighbor.story][neighbor.y][neighbor.x]) {
                count += 1
            }
        }
        return count
    }

    private func resolveSpawn(
        config: WorldSeedConfig,
        tiles: [[[Tile]]],
        width: Int,
        height: Int,
        stories: Int
    ) -> GridCoord {
        if let spawn = config.player.spawn {
            let coord = GridCoord(x: spawn.x, y: spawn.y, story: spawn.story)
            if coord.x >= 0, coord.x < width, coord.y >= 0, coord.y < height,
               coord.story >= 0, coord.story < stories,
               isFloor(tiles[coord.story][coord.y][coord.x]) {
                return coord
            }
        }

        for story in 0..<stories {
            for y in 0..<height {
                for x in 0..<width {
                    if isFloor(tiles[story][y][x]) {
                        return GridCoord(x: x, y: y, story: story)
                    }
                }
            }
        }

        return GridCoord(x: 1, y: 1, story: 0)
    }
}
