import Foundation

/// Deterministic min-entropy floor tile assigner using the baked matches map.
nonisolated struct FloorTiler: Sendable {
    struct Options: Sendable {
        var decorProb: Double

        init(decorProb: Double = 0.06) {
            self.decorProb = decorProb
        }
    }

    /// Salt so floor tiling does not perturb room/enemy/pickup RNG streams.
    static let seedSalt: UInt64 = 0xF1005E7

    /// Assigns `floorTileID` to every `.floor` tile on `story`.
    static func tile(
        tiles: inout [[Tile]],
        story: Int,
        set: FloorTileSet,
        options: Options,
        rng: inout SeededGenerator
    ) {
        let height = tiles.count
        guard height > 0 else { return }
        let width = tiles[0].count
        var coords: [GridCoord] = []
        for y in 0..<height {
            for x in 0..<width {
                if case .floor = tiles[y][x].kind {
                    coords.append(GridCoord(x: x, y: y, story: story))
                }
            }
        }
        solve(
            tiles: &tiles,
            width: width,
            height: height,
            coords: coords,
            set: set,
            options: options,
            rng: &rng
        )
    }

    /// Re-solves `coords` and their 4-neighbours (runtime mutations).
    static func retile(
        tiles: inout [[Tile]],
        story: Int,
        coords: [GridCoord],
        set: FloorTileSet,
        options: Options,
        rng: inout SeededGenerator
    ) {
        let height = tiles.count
        guard height > 0 else { return }
        let width = tiles[0].count
        var expanded = Set<GridCoord>()
        for coord in coords where coord.story == story {
            expanded.insert(coord)
            for side in FloorTileSet.Side.allCases {
                let d = FloorTileSet.delta(side)
                let n = GridCoord(x: coord.x + d.dx, y: coord.y + d.dy, story: story)
                if n.x >= 0, n.x < width, n.y >= 0, n.y < height {
                    expanded.insert(n)
                }
            }
        }
        let floorCoords = expanded
            .filter { coord in
                guard coord.y >= 0, coord.y < height, coord.x >= 0, coord.x < width else {
                    return false
                }
                if case .floor = tiles[coord.y][coord.x].kind { return true }
                return false
            }
            .sorted { a, b in
                if a.y != b.y { return a.y < b.y }
                return a.x < b.x
            }
        solve(
            tiles: &tiles,
            width: width,
            height: height,
            coords: floorCoords,
            set: set,
            options: options,
            rng: &rng
        )
    }

    // MARK: - Solver

    private static func solve(
        tiles: inout [[Tile]],
        width: Int,
        height: Int,
        coords: [GridCoord],
        set: FloorTileSet,
        options: Options,
        rng: inout SeededGenerator
    ) {
        guard !coords.isEmpty else { return }

        let floorIDs = set.floorTileIDs
        let decorIDs = set.decorTileIDs
        let pitIDs = Set(set.pitTileIDs)
        // Non-pit cells may only use floor/decor art — never pit frames.
        let nonPitIDs = Set(floorIDs).union(decorIDs).subtracting(pitIDs)
        let fallbackFloor = floorIDs.first
            ?? nonPitIDs.sorted().first
            ?? set.frames.keys.sorted().first { set.frames[$0]?.role != .pit }

        // Domains keyed by (x,y) within the story plane.
        var domains: [Int: Set<String>] = [:]
        for coord in coords {
            let key = coord.y * width + coord.x
            let tile = tiles[coord.y][coord.x]
            if tile.isPit {
                let mask = pitMask(at: coord, tiles: tiles, width: width, height: height)
                var candidates = Set(set.pitTiles(matching: mask)).intersection(pitIDs)
                if candidates.isEmpty {
                    candidates = pitIDs
                }
                if candidates.isEmpty {
                    candidates = Set(floorIDs)
                }
                domains[key] = candidates
            } else {
                var candidates = Set(floorIDs).subtracting(pitIDs)
                if !decorIDs.isEmpty, rng.nextBool(probability: options.decorProb) {
                    candidates.formUnion(Set(decorIDs).subtracting(pitIDs))
                }
                if candidates.isEmpty {
                    candidates = nonPitIDs
                }
                if candidates.isEmpty, let fallbackFloor {
                    candidates = [fallbackFloor]
                }
                domains[key] = candidates
            }
        }

        var undecided = Set(domains.keys)
        // Pre-seed domains from already-assigned neighbours outside the solve set
        // so retile respects surrounding art.
        for coord in coords {
            let key = coord.y * width + coord.x
            constrainAgainstAssignedNeighbours(
                key: key,
                coord: coord,
                tiles: tiles,
                width: width,
                height: height,
                domains: &domains,
                undecided: undecided,
                set: set
            )
        }

        while !undecided.isEmpty {
            // Min-entropy: smallest domain, ties by (y, x).
            let pickKey = undecided.min { a, b in
                let da = domains[a]?.count ?? 0
                let db = domains[b]?.count ?? 0
                if da != db { return da < db }
                let ay = a / width, ax = a % width
                let by = b / width, bx = b % width
                if ay != by { return ay < by }
                return ax < bx
            }!
            let y = pickKey / width
            let x = pickKey % width
            let coord = GridCoord(x: x, y: y, story: coords[0].story)

            var domain = domains[pickKey] ?? []
            if domain.isEmpty {
                domain = rescueDomain(
                    at: coord,
                    tiles: tiles,
                    width: width,
                    height: height,
                    set: set,
                    floorIDs: floorIDs,
                    nonPitIDs: nonPitIDs
                )
            }
            if !tiles[y][x].isPit {
                domain.subtract(pitIDs)
                if domain.isEmpty { domain = nonPitIDs }
            }

            var chosen = pickBestMatch(
                ids: Array(domain),
                at: coord,
                tiles: tiles,
                width: width,
                height: height,
                undecided: undecided,
                set: set,
                rng: &rng
            ) ?? domain.sorted().first ?? fallbackFloor
            // Final guard: never stamp a pit frame onto ordinary floor.
            if !tiles[y][x].isPit, let id = chosen, set.frames[id]?.role == .pit {
                chosen = fallbackFloor ?? nonPitIDs.sorted().first
            }
            guard let chosen else {
                undecided.remove(pickKey)
                continue
            }

            tiles[y][x].floorTileID = chosen
            undecided.remove(pickKey)
            domains[pickKey] = [chosen]

            // Arc-reduce neighbours still undecided.
            for side in FloorTileSet.Side.allCases {
                let d = FloorTileSet.delta(side)
                let nx = x + d.dx
                let ny = y + d.dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nKey = ny * width + nx
                guard undecided.contains(nKey) else { continue }
                var allowed = Set(set.frames[chosen]?.matches[side.rawValue] ?? [])
                if !tiles[ny][nx].isPit {
                    allowed.subtract(pitIDs)
                }
                if var nDomain = domains[nKey] {
                    if !allowed.isEmpty {
                        let narrowed = nDomain.intersection(allowed)
                        // Keep prior domain if intersection empties — rescue later.
                        if !narrowed.isEmpty {
                            nDomain = narrowed
                        }
                    }
                    if !tiles[ny][nx].isPit {
                        nDomain.subtract(pitIDs)
                    }
                    domains[nKey] = nDomain
                }
            }
        }
    }

    /// Prefer candidates that satisfy the most already-assigned neighbours' match lists.
    private static func pickBestMatch(
        ids: [String],
        at coord: GridCoord,
        tiles: [[Tile]],
        width: Int,
        height: Int,
        undecided: Set<Int>,
        set: FloorTileSet,
        rng: inout SeededGenerator
    ) -> String? {
        guard !ids.isEmpty else { return nil }

        var neighbourConstraints: [(side: FloorTileSet.Side, allowed: Set<String>)] = []
        for side in FloorTileSet.Side.allCases {
            let d = FloorTileSet.delta(side)
            let nx = coord.x + d.dx
            let ny = coord.y + d.dy
            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
            let nKey = ny * width + nx
            guard !undecided.contains(nKey),
                  case .floor = tiles[ny][nx].kind,
                  let nid = tiles[ny][nx].floorTileID else { continue }
            let opp = FloorTileSet.opposite(side)
            let allowed = Set(set.frames[nid]?.matches[opp.rawValue] ?? [])
            if !allowed.isEmpty {
                neighbourConstraints.append((side, allowed))
            }
        }

        guard !neighbourConstraints.isEmpty else {
            return weightedPick(ids: ids, set: set, rng: &rng)
        }

        var bestScore = -1
        var best: [String] = []
        for id in ids {
            var score = 0
            for constraint in neighbourConstraints {
                if constraint.allowed.contains(id) { score += 2 }
                // Bonus when this tile also lists the neighbour (symmetry / stronger edge).
                if let nid = neighbourID(
                    at: coord,
                    side: constraint.side,
                    tiles: tiles,
                    width: width,
                    height: height
                ),
                   (set.frames[id]?.matches[constraint.side.rawValue] ?? []).contains(nid) {
                    score += 1
                }
            }
            if score > bestScore {
                bestScore = score
                best = [id]
            } else if score == bestScore {
                best.append(id)
            }
        }
        return weightedPick(ids: best.isEmpty ? ids : best, set: set, rng: &rng)
    }

    private static func neighbourID(
        at coord: GridCoord,
        side: FloorTileSet.Side,
        tiles: [[Tile]],
        width: Int,
        height: Int
    ) -> String? {
        let d = FloorTileSet.delta(side)
        let nx = coord.x + d.dx
        let ny = coord.y + d.dy
        guard nx >= 0, nx < width, ny >= 0, ny < height else { return nil }
        return tiles[ny][nx].floorTileID
    }

    private static func pitMask(
        at coord: GridCoord,
        tiles: [[Tile]],
        width: Int,
        height: Int
    ) -> Set<FloorTileSet.Side> {
        var mask = Set<FloorTileSet.Side>()
        for side in FloorTileSet.Side.allCases {
            let d = FloorTileSet.delta(side)
            let nx = coord.x + d.dx
            let ny = coord.y + d.dy
            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
            if tiles[ny][nx].isPit {
                mask.insert(side)
            }
        }
        return mask
    }

    private static func constrainAgainstAssignedNeighbours(
        key: Int,
        coord: GridCoord,
        tiles: [[Tile]],
        width: Int,
        height: Int,
        domains: inout [Int: Set<String>],
        undecided: Set<Int>,
        set: FloorTileSet
    ) {
        guard var domain = domains[key] else { return }
        let pitIDs = Set(set.pitTileIDs)
        for side in FloorTileSet.Side.allCases {
            let d = FloorTileSet.delta(side)
            let nx = coord.x + d.dx
            let ny = coord.y + d.dy
            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
            let nKey = ny * width + nx
            // Neighbour already assigned and not part of this solve → hard constraint.
            if !undecided.contains(nKey),
               case .floor = tiles[ny][nx].kind,
               let nid = tiles[ny][nx].floorTileID,
               set.frames[nid] != nil {
                let opp = FloorTileSet.opposite(side)
                var allowed = Set(set.frames[nid]?.matches[opp.rawValue] ?? [])
                if !tiles[coord.y][coord.x].isPit {
                    allowed.subtract(pitIDs)
                }
                if !allowed.isEmpty {
                    domain = domain.intersection(allowed)
                }
            }
        }
        if !tiles[coord.y][coord.x].isPit {
            domain.subtract(pitIDs)
        }
        domains[key] = domain
    }

    private static func rescueDomain(
        at coord: GridCoord,
        tiles: [[Tile]],
        width: Int,
        height: Int,
        set: FloorTileSet,
        floorIDs: [String],
        nonPitIDs: Set<String>
    ) -> Set<String> {
        if tiles[coord.y][coord.x].isPit {
            let anyPit = Set(set.pitTileIDs)
            if !anyPit.isEmpty { return anyPit }
        }
        if !nonPitIDs.isEmpty { return nonPitIDs }
        if !floorIDs.isEmpty { return Set(floorIDs) }
        return Set(set.frames.keys.filter { set.frames[$0]?.role != .pit })
    }

    private static func weightedPick(
        ids: [String],
        set: FloorTileSet,
        rng: inout SeededGenerator
    ) -> String? {
        guard !ids.isEmpty else { return nil }
        let sorted = ids.sorted()
        var total = 0.0
        var weights: [Double] = []
        weights.reserveCapacity(sorted.count)
        for id in sorted {
            let w = max(set.frames[id]?.weight ?? 1, 0.0001)
            weights.append(w)
            total += w
        }
        var roll = Double(rng.next() % 10_000) / 10_000.0 * total
        for (index, id) in sorted.enumerated() {
            roll -= weights[index]
            if roll <= 0 { return id }
        }
        return sorted.last
    }
}
