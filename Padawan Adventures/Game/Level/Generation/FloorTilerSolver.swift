import Foundation



nonisolated extension FloorTiler {
    // MARK: - Solver

    static func solve(
        tiles: inout [[Tile]],
        width: Int,
        height: Int,
        coords: [GridCoord],
        set: FloorTileSet,
        options: Options,
        rooms: [GeneratedRoom],
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
        let fallbackPit = pitIDs.sorted().first

        // One palette per group (a room when the caller supplied rooms). Falls
        // back to per-region families for atlases baked before palettes.
        let groupList = groups(
            coords: coords, rooms: rooms, tiles: tiles, width: width, height: height
        )
        let hasPalettes = !set.paletteIDsWeighted.isEmpty
        let adjacency = hasPalettes ? adjacentGroups(groupList) : [:]
        var paletteByKey: [Int: String] = [:]
        var paletteByGroup: [Int: String] = [:]
        var familyByKey: [Int: String] = [:]
        var usedFamilies = Set<String>()

        for (index, group) in groupList.enumerated() {
            let undecided = Set(group.map { $0.y * width + $0.x })
            if hasPalettes {
                let inherited = inheritPalette(
                    region: group,
                    tiles: tiles,
                    width: width,
                    height: height,
                    undecided: undecided,
                    set: set
                )
                // Only neighbouring groups are penalised, so distant rooms may
                // reuse a palette while adjacent ones stay distinct.
                let penalize = Set(
                    (adjacency[index] ?? []).compactMap { paletteByGroup[$0] }
                )
                let chosen = inherited
                    ?? pickPalette(set: set, penalize: penalize, rng: &rng)
                if let chosen {
                    paletteByGroup[index] = chosen
                    for coord in group {
                        paletteByKey[coord.y * width + coord.x] = chosen
                    }
                }
                continue
            }
            let inherited = inheritFamily(
                region: group,
                tiles: tiles,
                width: width,
                height: height,
                undecided: undecided,
                set: set
            )
            let chosen = inherited
                ?? pickDominantFamily(set: set, penalize: usedFamilies, rng: &rng)
            if let chosen {
                usedFamilies.insert(chosen)
                for coord in group {
                    familyByKey[coord.y * width + coord.x] = chosen
                }
            }
        }

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
                var candidates: Set<String>
                if let palette = paletteByKey[key],
                   !set.tileIDs(palette: palette).isEmpty {
                    candidates = Set(set.tileIDs(palette: palette)).subtracting(pitIDs)
                    // A palette already carries its own decor, so gate that
                    // decor down to decorProb rather than unioning outside art
                    // in — off-palette decor is exactly what breaks a floor.
                    let paletteDecor = Set(decorIDs).intersection(candidates)
                    if !paletteDecor.isEmpty,
                       !rng.nextBool(probability: options.decorProb) {
                        candidates.subtract(paletteDecor)
                    }
                } else if let dominant = familyByKey[key],
                          !set.tileIDs(family: dominant).isEmpty {
                    candidates = Set(set.tileIDs(family: dominant)).subtracting(pitIDs)
                    // Off-family accents apply only to palette-less atlases.
                    if options.accentProb > 0,
                       rng.nextBool(probability: options.accentProb) {
                        candidates = Set(floorIDs).subtracting(pitIDs)
                    }
                    if !decorIDs.isEmpty, rng.nextBool(probability: options.decorProb) {
                        candidates.formUnion(Set(decorIDs).subtracting(pitIDs))
                    }
                } else {
                    candidates = Set(floorIDs).subtracting(pitIDs)
                    if !decorIDs.isEmpty, rng.nextBool(probability: options.decorProb) {
                        candidates.formUnion(Set(decorIDs).subtracting(pitIDs))
                    }
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
            if tiles[y][x].isPit {
                if !pitIDs.isEmpty {
                    let narrowed = domain.intersection(pitIDs)
                    domain = narrowed.isEmpty ? pitIDs : narrowed
                }
            } else {
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
                options: options,
                rng: &rng
            ) ?? domain.sorted().first ?? fallbackFloor
            // Never mix the two art pools, whatever the solver produced.
            if let id = chosen {
                if tiles[y][x].isPit, set.frames[id]?.role != .pit, let fallbackPit {
                    chosen = fallbackPit
                } else if !tiles[y][x].isPit, set.frames[id]?.role == .pit {
                    chosen = fallbackFloor ?? nonPitIDs.sorted().first
                }
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
                if tiles[ny][nx].isPit {
                    if !pitIDs.isEmpty { allowed.formIntersection(pitIDs) }
                } else {
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
                    if tiles[ny][nx].isPit {
                        if !pitIDs.isEmpty {
                            let keep = nDomain.intersection(pitIDs)
                            if !keep.isEmpty { nDomain = keep }
                        }
                    } else {
                        nDomain.subtract(pitIDs)
                    }
                    domains[nKey] = nDomain
                }
            }
        }
    }

    /// Prefer candidates that satisfy the most already-assigned neighbours' match lists,
    /// with a cohesion bias toward repeating neighbour tile ids / families.
    static func pickBestMatch(
        ids: [String],
        at coord: GridCoord,
        tiles: [[Tile]],
        width: Int,
        height: Int,
        undecided: Set<Int>,
        set: FloorTileSet,
        options: Options,
        rng: inout SeededGenerator
    ) -> String? {
        guard !ids.isEmpty else { return nil }

        var neighbourConstraints: [(side: FloorTileSet.Side, allowed: Set<String>)] = []
        var assignedNeighbourIDs = Set<String>()
        var assignedNeighbourFamilies = Set<String?>()
        for side in FloorTileSet.Side.allCases {
            let d = FloorTileSet.delta(side)
            let nx = coord.x + d.dx
            let ny = coord.y + d.dy
            guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
            let nKey = ny * width + nx
            guard !undecided.contains(nKey),
                  case .floor = tiles[ny][nx].kind,
                  let nid = tiles[ny][nx].floorTileID else { continue }
            assignedNeighbourIDs.insert(nid)
            assignedNeighbourFamilies.insert(set.frames[nid]?.family)
            let opp = FloorTileSet.opposite(side)
            let allowed = Set(set.frames[nid]?.matches[opp.rawValue] ?? [])
            if !allowed.isEmpty {
                neighbourConstraints.append((side, allowed))
            }
        }

        let clump = Int((options.cohesion * 8).rounded())

        guard !neighbourConstraints.isEmpty || clump > 0 else {
            return weightedPick(ids: ids, set: set, rng: &rng)
        }

        var bestScore = Int.min
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
            if clump > 0 {
                if assignedNeighbourIDs.contains(id) {
                    score += clump
                } else if assignedNeighbourFamilies.contains(set.frames[id]?.family) {
                    score += clump / 2
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

    static func neighbourID(
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

    static func pitMask(
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

    static func constrainAgainstAssignedNeighbours(
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
                if tiles[coord.y][coord.x].isPit {
                    if !pitIDs.isEmpty { allowed.formIntersection(pitIDs) }
                } else {
                    allowed.subtract(pitIDs)
                }
                if !allowed.isEmpty {
                    let narrowed = domain.intersection(allowed)
                    // Keep prior domain if intersection empties — rescue later.
                    if !narrowed.isEmpty {
                        domain = narrowed
                    }
                }
            }
        }
        if tiles[coord.y][coord.x].isPit {
            if !pitIDs.isEmpty {
                let keep = domain.intersection(pitIDs)
                if !keep.isEmpty { domain = keep }
            }
        } else {
            domain.subtract(pitIDs)
        }
        domains[key] = domain
    }

    static func rescueDomain(
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

    static func weightedPick(
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

    /// Modal family of already-assigned neighbours outside `undecided`, if any.
    static func inheritFamily(
        region: [GridCoord],
        tiles: [[Tile]],
        width: Int,
        height: Int,
        undecided: Set<Int>,
        set: FloorTileSet
    ) -> String? {
        var counts: [String: Int] = [:]
        for coord in region {
            for side in FloorTileSet.Side.allCases {
                let d = FloorTileSet.delta(side)
                let nx = coord.x + d.dx
                let ny = coord.y + d.dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nKey = ny * width + nx
                guard !undecided.contains(nKey),
                      case .floor = tiles[ny][nx].kind,
                      let nid = tiles[ny][nx].floorTileID,
                      let fam = set.frames[nid]?.family else { continue }
                counts[fam, default: 0] += 1
            }
        }
        guard !counts.isEmpty else { return nil }
        // Deterministic: highest count, then lexicographically smallest id.
        return counts.keys.sorted { a, b in
            let ca = counts[a] ?? 0
            let cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return a < b
        }.first
    }

    /// Modal palette among already-assigned neighbours outside `undecided`.
    /// Palettes overlap, so every palette a neighbour belongs to gets a vote.
    static func inheritPalette(
        region: [GridCoord],
        tiles: [[Tile]],
        width: Int,
        height: Int,
        undecided: Set<Int>,
        set: FloorTileSet
    ) -> String? {
        var counts: [String: Int] = [:]
        for coord in region {
            for side in FloorTileSet.Side.allCases {
                let d = FloorTileSet.delta(side)
                let nx = coord.x + d.dx
                let ny = coord.y + d.dy
                guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                let nKey = ny * width + nx
                guard !undecided.contains(nKey),
                      case .floor = tiles[ny][nx].kind,
                      let nid = tiles[ny][nx].floorTileID else { continue }
                for palette in set.paletteIDs(containing: nid) {
                    counts[palette, default: 0] += 1
                }
            }
        }
        guard !counts.isEmpty else { return nil }
        // Deterministic: highest count, then lexicographically smallest id.
        return counts.keys.sorted { a, b in
            let ca = counts[a] ?? 0
            let cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return a < b
        }.first
    }

    /// Weighted palette pick. The penalty applies to adjacent groups only and
    /// is heavy, so neighbouring rooms rarely share a palette.
    static func pickPalette(
        set: FloorTileSet,
        penalize: Set<String>,
        rng: inout SeededGenerator
    ) -> String? {
        let weighted = set.paletteIDsWeighted
        guard !weighted.isEmpty else { return nil }
        let sorted = weighted.sorted { $0.id < $1.id }
        var total = 0.0
        var weights: [Double] = []
        weights.reserveCapacity(sorted.count)
        for entry in sorted {
            let w = entry.weight * (penalize.contains(entry.id) ? 0.05 : 1.0)
            weights.append(max(w, 0.0001))
            total += max(w, 0.0001)
        }
        var roll = Double(rng.next() % 10_000) / 10_000.0 * total
        for (index, entry) in sorted.enumerated() {
            roll -= weights[index]
            if roll <= 0 { return entry.id }
        }
        return sorted.last?.id
    }

    /// Weighted family pick with a 0.25× penalty on already-used families.
    static func pickDominantFamily(
        set: FloorTileSet,
        penalize: Set<String>,
        rng: inout SeededGenerator
    ) -> String? {
        let weighted = set.familyIDsWeighted
        guard !weighted.isEmpty else { return nil }
        let sorted = weighted.sorted { $0.id < $1.id }
        var total = 0.0
        var weights: [Double] = []
        weights.reserveCapacity(sorted.count)
        for entry in sorted {
            let w = entry.weight * (penalize.contains(entry.id) ? 0.25 : 1.0)
            weights.append(max(w, 0.0001))
            total += max(w, 0.0001)
        }
        var roll = Double(rng.next() % 10_000) / 10_000.0 * total
        for (index, entry) in sorted.enumerated() {
            roll -= weights[index]
            if roll <= 0 { return entry.id }
        }
        return sorted.last?.id
    }

}
