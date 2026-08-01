import Foundation

extension ProceduralGenerator {
    /// Rolls `chance` once per room; on success places a contiguous pit area in that room.
    func sprinklePits(
        rooms: [GeneratedRoom],
        into story: inout [[Tile]],
        chance: Double,
        meanSize: Double,
        maxSize: Int,
        excludingRoomID: Int,
        excluding spawn: GridCoord,
        rng: inout SeededGenerator
    ) {
        let ordered = rooms.sorted { $0.id < $1.id }
        for room in ordered {
            guard room.id != excludingRoomID else { continue }
            guard rng.nextBool(probability: chance) else { continue }

            let candidates = room.cells
                .filter { cell in
                    guard cell != spawn else { return false }
                    guard case .floor(let isPit) = story[cell.y][cell.x].kind else { return false }
                    return !isPit
                }
                .sorted { lhs, rhs in
                    if lhs.x != rhs.x { return lhs.x < rhs.x }
                    return lhs.y < rhs.y
                }
            guard let seed = rng.pick(candidates) else { continue }

            let target = samplePitTileCount(mean: meanSize, maxSize: maxSize, rng: &rng)
            let area = growContiguousPit(
                from: seed,
                targetCount: target,
                roomCells: room.cells,
                excluding: [spawn],
                in: story,
                rng: &rng
            )
            for cell in area {
                story[cell.y][cell.x] = Tile(kind: .floor(isPit: true))
            }
        }
    }

    /// Samples a pit size in `1...maxSize` with expected value ≈ `mean` via successive growth.
    func samplePitTileCount(
        mean: Double,
        maxSize: Int,
        rng: inout SeededGenerator
    ) -> Int {
        let maxS = max(1, maxSize)
        let mu = min(Double(maxS), max(1.0, mean))
        if mu >= Double(maxS) - 1e-9 { return maxS }
        if mu <= 1.0 + 1e-9 { return 1 }

        let growthP = pitGrowthProbability(forMean: mu, maxSize: maxS)
        var count = 1
        while count < maxS && rng.nextBool(probability: growthP) {
            count += 1
        }
        return count
    }

    /// Growth probability `p` such that `E[1 + sum I_k] ≈ mean` for max `maxSize` steps.
    func pitGrowthProbability(forMean mean: Double, maxSize: Int) -> Double {
        // E = (1 - p^n) / (1 - p) for p ∈ [0, 1), n = maxSize.
        var lo = 0.0
        var hi = 0.999_999
        for _ in 0..<48 {
            let mid = (lo + hi) * 0.5
            let expected = (1 - pow(mid, Double(maxSize))) / (1 - mid)
            if expected < mean {
                lo = mid
            } else {
                hi = mid
            }
        }
        return (lo + hi) * 0.5
    }

    /// Grows a contiguous pit blob inside a room via random frontier expansion.
    func growContiguousPit(
        from seed: GridCoord,
        targetCount: Int,
        roomCells: Set<GridCoord>,
        excluding blocked: Set<GridCoord>,
        in story: [[Tile]],
        rng: inout SeededGenerator
    ) -> [GridCoord] {
        var area = [seed]
        var inArea: Set<GridCoord> = [seed]
        var frontier: [GridCoord] = []

        func consider(_ cell: GridCoord) {
            guard roomCells.contains(cell), !blocked.contains(cell), !inArea.contains(cell) else { return }
            guard case .floor(let isPit) = story[cell.y][cell.x].kind, !isPit else { return }
            if !frontier.contains(where: { $0 == cell }) {
                frontier.append(cell)
            }
        }

        for (dx, dy) in GridCoord.cardinals {
            consider(seed.neighbor(dx: dx, dy: dy))
        }
        frontier.sort { ($0.x, $0.y) < ($1.x, $1.y) }

        while area.count < targetCount, !frontier.isEmpty {
            guard let pick = rng.pick(frontier) else { break }
            frontier.removeAll { $0 == pick }
            area.append(pick)
            inArea.insert(pick)
            for (dx, dy) in GridCoord.cardinals {
                consider(pick.neighbor(dx: dx, dy: dy))
            }
            frontier.sort { ($0.x, $0.y) < ($1.x, $1.y) }
        }
        return area
    }

    func clearPits(around spawn: GridCoord, tiles: inout [[[Tile]]], story: Int) {
        var coords = [spawn]
        for (dx, dy) in GridCoord.cardinals {
            coords.append(spawn.neighbor(dx: dx, dy: dy))
        }
        for coord in coords {
            guard coord.y >= 0, coord.y < tiles[story].count else { continue }
            guard coord.x >= 0, coord.x < tiles[story][coord.y].count else { continue }
            if case .floor = tiles[story][coord.y][coord.x].kind {
                tiles[story][coord.y][coord.x] = Tile(kind: .floor(isPit: false))
            }
        }
    }

    /// Places a single pit blob in the first eligible non-spawn room.
    @discardableResult
    func forceOnePit(
        rooms: [GeneratedRoom],
        into story: inout [[Tile]],
        meanSize: Double,
        maxSize: Int,
        excludingRoomID: Int,
        excluding blocked: Set<GridCoord>,
        rng: inout SeededGenerator
    ) -> Bool {
        let ordered = rooms.sorted { $0.id < $1.id }
        for room in ordered where room.id != excludingRoomID {
            let candidates = room.cells
                .filter { cell in
                    guard !blocked.contains(cell) else { return false }
                    guard case .floor(let isPit) = story[cell.y][cell.x].kind else { return false }
                    return !isPit
                }
                .sorted { lhs, rhs in
                    if lhs.x != rhs.x { return lhs.x < rhs.x }
                    return lhs.y < rhs.y
                }
            guard let seed = rng.pick(candidates) else { continue }

            let target = samplePitTileCount(mean: meanSize, maxSize: maxSize, rng: &rng)
            let area = growContiguousPit(
                from: seed,
                targetCount: target,
                roomCells: room.cells,
                excluding: blocked,
                in: story,
                rng: &rng
            )
            for cell in area {
                story[cell.y][cell.x] = Tile(kind: .floor(isPit: true))
            }
            return !area.isEmpty
        }
        return false
    }

    func runPitsPass(state: inout GenerationAttemptState, config: WorldGenerationConfig) {
        let params = config.generation
        sprinklePits(
            rooms: state.rooms,
            into: &state.tiles[0],
            chance: params.room.pitChance,
            meanSize: params.room.pitMeanSize,
            maxSize: params.room.pitMaxSize,
            excludingRoomID: state.topRight.id,
            excluding: state.spawn,
            rng: &state.rng
        )
        clearPits(around: state.spawn, tiles: &state.tiles, story: 0)
    }
}
