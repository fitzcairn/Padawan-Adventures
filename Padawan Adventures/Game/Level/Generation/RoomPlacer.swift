import Foundation

nonisolated extension ProceduralGenerator {
    // MARK: - Room placement

    func filledWalls(width: Int, height: Int, stories: Int) -> [[[Tile]]] {
        Array(
            repeating: Array(
                repeating: Array(
                    repeating: Tile(kind: .wall),
                    count: width
                ),
                count: height
            ),
            count: stories
        )
    }

    /// Packs rooms so every room after the first sits exactly one wall tile from an
    /// already-placed room, with room for a 2-cell gate in that wall.
    func placePackedRooms(
        count: Int,
        minSize: Int,
        maxSize: Int,
        shape: LevelConfig.RoomShape = .organic,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> [GeneratedRoom] {
        var rooms: [GeneratedRoom] = []
        var occupied = Set<GridCoord>()
        let attemptsPerRoom = 40
        /// After this many misses, organic/round-ish use compact L-rooms to fill leftover pockets.
        let lFallbackAfter = attemptsPerRoom / 4
        /// Last-ditch compact rect if an L will not seat; keeps tight maps at full room_count.
        let rectLastResortAfter = attemptsPerRoom - 8

        while rooms.count < count {
            var placed = false
            for attempt in 0..<attemptsPerRoom {
                let cap = max(minSize, maxSize - (maxSize - minSize) * attempt / attemptsPerRoom)
                let useLFallback: Bool
                switch shape {
                case .rect:
                    // Coruscant: keep today's rect/L mix (no rect stretch).
                    useLFallback = rng.nextBool(probability: 0.55)
                case .organic, .roundIsh:
                    useLFallback = attempt >= lFallbackAfter
                }

                let raw: Set<GridCoord>
                // Last-ditch organic/round-ish rects may shrink below `minSize` to fill a
                // leftover pocket that cannot host another primary room.
                var shapeMinSize = minSize
                if useLFallback {
                    switch shape {
                    case .rect:
                        // Coruscant: long-arm L fillers for leftover map.
                        raw = makeOrganicLRoom(
                            minSize: minSize,
                            maxSize: cap,
                            width: width,
                            height: height,
                            allowStretch: true,
                            rng: &rng
                        )
                    case .organic, .roundIsh:
                        if attempt >= rectLastResortAfter {
                            shapeMinSize = min(minSize, 3)
                            raw = makeRectRoom(
                                minSize: shapeMinSize,
                                maxSize: minSize,
                                width: width,
                                height: height,
                                rng: &rng
                            )
                        } else {
                            raw = makeOrganicLRoom(
                                minSize: minSize,
                                maxSize: cap,
                                width: width,
                                height: height,
                                allowStretch: false,
                                rng: &rng
                            )
                        }
                    }
                } else {
                    switch shape {
                    case .organic:
                        raw = makeOrganicBlobRoom(
                            minSize: minSize,
                            maxSize: cap,
                            width: width,
                            height: height,
                            rng: &rng
                        )
                    case .roundIsh:
                        raw = makeRoundIshRoom(
                            minSize: minSize,
                            maxSize: cap,
                            width: width,
                            height: height,
                            rng: &rng
                        )
                    case .rect:
                        raw = makeRectRoom(
                            minSize: minSize,
                            maxSize: cap,
                            width: width,
                            height: height,
                            rng: &rng
                        )
                    }
                }
                let shapeCells = normalizeShape(raw)
                guard !shapeCells.isEmpty, isAtLeastTwoWide(Set(shapeCells)) else { continue }
                let bbox = boundingSize(of: shapeCells)
                guard bbox.w >= shapeMinSize, bbox.h >= shapeMinSize else { continue }
                // Stretched rect-mode L fillers may exceed max, but a filled rectangle
                // is a primary room (or a degenerate L) and must stay in range.
                let isFilledRect = shapeCells.count == bbox.w * bbox.h
                let mayExceedMax = useLFallback && shape == .rect && !isFilledRect
                if !mayExceedMax {
                    guard bbox.w <= maxSize, bbox.h <= maxSize else { continue }
                }

                let cells: Set<GridCoord>?
                if rooms.isEmpty {
                    cells = firstOriginPlacement(
                        shape: shapeCells,
                        occupied: occupied,
                        width: width,
                        height: height,
                        rng: &rng
                    )
                } else {
                    var found: Set<GridCoord>?
                    let anchors = rooms.shuffled(using: &rng)
                    for anchor in anchors {
                        if let placement = firstLegalPlacement(
                            shape: shapeCells,
                            anchor: anchor,
                            occupied: occupied,
                            width: width,
                            height: height,
                            rng: &rng
                        ) {
                            found = placement
                            break
                        }
                    }
                    cells = found
                }

                guard let cells else { continue }
                occupied.formUnion(cells)
                rooms.append(
                    GeneratedRoom(
                        id: rooms.count,
                        cells: cells,
                        center: centroid(of: cells),
                        latticeX: 0,
                        latticeY: 0
                    )
                )
                placed = true
                break
            }
            if !placed { break }
        }

        return rooms
    }

    /// Translate shape cells so min x/y are zero; returns sorted list for determinism.
    func normalizeShape(_ cells: Set<GridCoord>) -> [GridCoord] {
        guard let minX = cells.map(\.x).min(), let minY = cells.map(\.y).min() else { return [] }
        return cells
            .map { GridCoord(x: $0.x - minX, y: $0.y - minY, story: 0) }
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    /// Place the first room at a random legal origin (1-tile map margin).
    func firstOriginPlacement(
        shape: [GridCoord],
        occupied: Set<GridCoord>,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord>? {
        guard let maxX = shape.map(\.x).max(), let maxY = shape.map(\.y).max() else { return nil }
        let shapeW = maxX + 1
        let shapeH = maxY + 1
        guard width > shapeW + 1, height > shapeH + 1 else { return nil }
        let maxOx = width - 1 - shapeW
        let maxOy = height - 1 - shapeH
        guard maxOx >= 1, maxOy >= 1 else { return nil }
        for _ in 0..<16 {
            let ox = rng.nextInt(upperBound: maxOx) + 1
            let oy = rng.nextInt(upperBound: maxOy) + 1
            let cells = Set(shape.map { GridCoord(x: $0.x + ox, y: $0.y + oy, story: 0) })
            if isLegalPackedPlacement(cells, occupied: occupied, width: width, height: height) {
                return cells
            }
        }
        return nil
    }

    /// Origins that put one shape cell exactly two tiles from one anchor cell,
    /// i.e. with a single wall tile between them.
    func candidateOrigins(
        shape: [GridCoord],
        anchor: GeneratedRoom,
        rng: inout SeededGenerator
    ) -> [GridCoord] {
        let anchorCells = anchor.cells
            .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            .shuffled(using: &rng)
            .prefix(16)
        let shapeCells = shape.shuffled(using: &rng).prefix(16)
        let dirs = GridCoord.cardinals.shuffled(using: &rng)
        var origins: [GridCoord] = []
        var seen = Set<GridCoord>()
        for a in anchorCells {
            for d in dirs {
                for c in shapeCells {
                    let origin = GridCoord(
                        x: a.x + 2 * d.dx - c.x,
                        y: a.y + 2 * d.dy - c.y,
                        story: 0
                    )
                    if seen.insert(origin).inserted {
                        origins.append(origin)
                        if origins.count >= 256 { return origins }
                    }
                }
            }
        }
        return origins
    }

    /// First candidate origin that yields a legal packed placement, or nil.
    func firstLegalPlacement(
        shape: [GridCoord],
        anchor: GeneratedRoom,
        occupied: Set<GridCoord>,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord>? {
        for origin in candidateOrigins(shape: shape, anchor: anchor, rng: &rng) {
            let cells = Set(shape.map {
                GridCoord(x: $0.x + origin.x, y: $0.y + origin.y, story: 0)
            })
            guard isLegalPackedPlacement(cells, occupied: occupied, width: width, height: height)
            else { continue }
            guard hasSharedWallGateCandidate(cells, anchor: anchor, occupied: occupied)
            else { continue }
            return cells
        }
        return nil
    }

    /// In-bounds (keeping the 1-tile map margin), not overlapping, and never
    /// cardinally touching another room's floor.
    func isLegalPackedPlacement(
        _ cells: Set<GridCoord>,
        occupied: Set<GridCoord>,
        width: Int,
        height: Int
    ) -> Bool {
        for cell in cells {
            guard cell.x >= 1, cell.x <= width - 2 else { return false }
            guard cell.y >= 1, cell.y <= height - 2 else { return false }
        }
        guard cells.isDisjoint(with: occupied) else { return false }
        let touchesExisting = cells.contains { cell in
            GridCoord.cardinals.contains { dx, dy in
                occupied.contains(cell.neighbor(dx: dx, dy: dy))
            }
        }
        return !touchesExisting
    }

    /// True when the wall between `cells` and `anchor` has two contiguous cells that
    /// could host a gate strip, with non-floor cells flanking either end.
    func hasSharedWallGateCandidate(
        _ cells: Set<GridCoord>,
        anchor: GeneratedRoom,
        occupied: Set<GridCoord>
    ) -> Bool {
        for d in GridCoord.cardinals {
            let wallCells = cells.compactMap { c -> GridCoord? in
                let beyond = c.neighbor(dx: 2 * d.dx, dy: 2 * d.dy)
                guard anchor.cells.contains(beyond) else { return nil }
                return c.neighbor(dx: d.dx, dy: d.dy)
            }
            let along = (dx: -d.dy, dy: d.dx)
            let ordered = Set(wallCells).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            for w1 in ordered {
                let w2 = w1.neighbor(dx: along.dx, dy: along.dy)
                guard ordered.contains(w2) else { continue }
                let before = w1.neighbor(dx: -along.dx, dy: -along.dy)
                let after = w2.neighbor(dx: along.dx, dy: along.dy)
                let flanksClear =
                    !occupied.contains(before) && !cells.contains(before)
                    && !occupied.contains(after) && !cells.contains(after)
                if flanksClear { return true }
            }
        }
        return false
    }

    /// Axis-aligned rectangle with both sides rolled in `[minSize, maxSize]`.
    func makeRectRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let w = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let h = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        guard width > w + 2, height > h + 2 else { return [] }

        let x = rng.nextInt(upperBound: width - w - 1) + 1
        let y = rng.nextInt(upperBound: height - h - 1) + 1

        var cells = Set<GridCoord>()
        for row in y..<(y + h) {
            for col in x..<(x + w) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }
        return cells
    }

    /// Cave-like blob grown inside a `w×h` box rolled in `[minSize, maxSize]`.
    func makeOrganicBlobRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let w = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let h = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        guard width > w + 2, height > h + 2 else { return [] }

        let x = rng.nextInt(upperBound: width - w - 1) + 1
        let y = rng.nextInt(upperBound: height - h - 1) + 1
        let boxArea = w * h
        let fillFraction = 0.65 + Double(rng.nextInt(upperBound: 21)) / 100.0  // 65–85%
        let target = max(minSize * minSize, Int((Double(boxArea) * fillFraction).rounded()))

        let seed = GridCoord(
            x: x + w / 2 + rng.nextInt(upperBound: 3) - 1,
            y: y + h / 2 + rng.nextInt(upperBound: 3) - 1,
            story: 0
        )
        let clampedSeed = GridCoord(
            x: min(max(seed.x, x), x + w - 1),
            y: min(max(seed.y, y), y + h - 1),
            story: 0
        )

        var cells: Set<GridCoord> = [clampedSeed]
        var frontier: [GridCoord] = []

        func inBox(_ cell: GridCoord) -> Bool {
            cell.x >= x && cell.x < x + w && cell.y >= y && cell.y < y + h
        }
        func consider(_ cell: GridCoord) {
            guard inBox(cell), !cells.contains(cell) else { return }
            if !frontier.contains(where: { $0 == cell }) {
                frontier.append(cell)
            }
        }

        for (dx, dy) in GridCoord.cardinals {
            consider(clampedSeed.neighbor(dx: dx, dy: dy))
        }
        frontier.sort { ($0.x, $0.y) < ($1.x, $1.y) }

        while cells.count < target, !frontier.isEmpty {
            guard let pick = rng.pick(frontier) else { break }
            frontier.removeAll { $0 == pick }
            cells.insert(pick)
            for (dx, dy) in GridCoord.cardinals {
                consider(pick.neighbor(dx: dx, dy: dy))
            }
            frontier.sort { ($0.x, $0.y) < ($1.x, $1.y) }
        }
        // Keep growing toward unused box edges so the final bbox stays the rolled min–max size.
        while !touchesBoxEdges(cells, x: x, y: y, w: w, h: h), !frontier.isEmpty {
            let ranked = frontier.sorted { a, b in
                let sa = boxEdgeScore(a, x: x, y: y, w: w, h: h)
                let sb = boxEdgeScore(b, x: x, y: y, w: w, h: h)
                if sa != sb { return sa > sb }
                return (a.x, a.y) < (b.x, b.y)
            }
            guard let pick = ranked.first else { break }
            frontier.removeAll { $0 == pick }
            cells.insert(pick)
            for (dx, dy) in GridCoord.cardinals {
                consider(pick.neighbor(dx: dx, dy: dy))
            }
        }
        thickenToMinimumWidth(&cells, allowed: inBox)
        guard isAtLeastTwoWide(cells), isPrimarySize(cells, minSize: minSize, maxSize: maxSize)
        else { return [] }
        return cells
    }

    /// Disk/ellipse inscribed in a min–max box, then lightly nibbled on the perimeter.
    func makeRoundIshRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let w = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let h = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        guard width > w + 2, height > h + 2 else { return [] }

        let originX = rng.nextInt(upperBound: width - w - 1) + 1
        let originY = rng.nextInt(upperBound: height - h - 1) + 1
        let cx = Double(originX) + Double(w - 1) / 2.0
        let cy = Double(originY) + Double(h - 1) / 2.0
        let rx = Double(w) / 2.0
        let ry = Double(h) / 2.0
        guard rx > 0, ry > 0 else { return [] }

        var cells = Set<GridCoord>()
        for row in originY..<(originY + h) {
            for col in originX..<(originX + w) {
                let dx = (Double(col) - cx) / rx
                let dy = (Double(row) - cy) / ry
                if dx * dx + dy * dy <= 1.0 {
                    cells.insert(GridCoord(x: col, y: row, story: 0))
                }
            }
        }
        guard cells.count >= 4 else { return cells }

        // Chew a modest fraction of perimeter cells without breaking contiguity.
        let nibbleBudget = max(1, cells.count / 8)
        for _ in 0..<nibbleBudget {
            let perimeter = cells.filter { cell in
                GridCoord.cardinals.contains { dx, dy in
                    !cells.contains(cell.neighbor(dx: dx, dy: dy))
                }
            }
            let candidates = Array(perimeter).filter { !isArticulationPoint($0, in: cells) }
            guard let victim = rng.pick(candidates), cells.count > 4 else { break }
            var next = cells
            next.remove(victim)
            guard isAtLeastTwoWide(next), isPrimarySize(next, minSize: minSize, maxSize: maxSize)
            else { continue }
            cells = next
        }
        guard isAtLeastTwoWide(cells), isPrimarySize(cells, minSize: minSize, maxSize: maxSize)
        else { return [] }
        return cells
    }

    func boundingSize(of cells: some Collection<GridCoord>) -> (w: Int, h: Int) {
        guard let minX = cells.map(\.x).min(), let maxX = cells.map(\.x).max(),
              let minY = cells.map(\.y).min(), let maxY = cells.map(\.y).max()
        else { return (0, 0) }
        return (maxX - minX + 1, maxY - minY + 1)
    }

    func isPrimarySize(_ cells: some Collection<GridCoord>, minSize: Int, maxSize: Int) -> Bool {
        let bbox = boundingSize(of: cells)
        return bbox.w >= minSize && bbox.w <= maxSize && bbox.h >= minSize && bbox.h <= maxSize
    }

    func touchesBoxEdges(_ cells: Set<GridCoord>, x: Int, y: Int, w: Int, h: Int) -> Bool {
        cells.contains { $0.x == x }
            && cells.contains { $0.x == x + w - 1 }
            && cells.contains { $0.y == y }
            && cells.contains { $0.y == y + h - 1 }
    }

    func boxEdgeScore(_ cell: GridCoord, x: Int, y: Int, w: Int, h: Int) -> Int {
        var score = 0
        if cell.x == x || cell.x == x + w - 1 { score += 1 }
        if cell.y == y || cell.y == y + h - 1 { score += 1 }
        return score
    }

    /// True when every cell sits in a filled 2×2, so the room is never a 1-tile corridor.
    func isAtLeastTwoWide(_ cells: Set<GridCoord>) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cellBelongsToTwoByTwo($0, in: cells) }
    }

    func cellBelongsToTwoByTwo(_ cell: GridCoord, in cells: Set<GridCoord>) -> Bool {
        let origins = [
            cell,
            cell.neighbor(dx: -1, dy: 0),
            cell.neighbor(dx: 0, dy: -1),
            cell.neighbor(dx: -1, dy: -1),
        ]
        return origins.contains { origin in
            cells.contains(origin)
                && cells.contains(origin.neighbor(dx: 1, dy: 0))
                && cells.contains(origin.neighbor(dx: 0, dy: 1))
                && cells.contains(origin.neighbor(dx: 1, dy: 1))
        }
    }

    /// Adds in-bounds neighbors so 1-tile fingers become 2-wide, when a single fill-in will do it.
    func thickenToMinimumWidth(
        _ cells: inout Set<GridCoord>,
        allowed: (GridCoord) -> Bool
    ) {
        var changed = true
        while changed {
            changed = false
            let thin = cells
                .filter { !cellBelongsToTwoByTwo($0, in: cells) }
                .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            for cell in thin {
                let origins = [
                    cell,
                    cell.neighbor(dx: -1, dy: 0),
                    cell.neighbor(dx: 0, dy: -1),
                    cell.neighbor(dx: -1, dy: -1),
                ]
                var added: GridCoord?
                for origin in origins {
                    let quad = [
                        origin,
                        origin.neighbor(dx: 1, dy: 0),
                        origin.neighbor(dx: 0, dy: 1),
                        origin.neighbor(dx: 1, dy: 1),
                    ]
                    let missing = quad.filter { !cells.contains($0) }
                    guard missing.count == 1, let fill = missing.first, allowed(fill) else { continue }
                    added = fill
                    break
                }
                if let added {
                    cells.insert(added)
                    changed = true
                }
            }
        }
    }

    /// True when removing `cell` would split the remaining set into multiple components.
    func isArticulationPoint(_ cell: GridCoord, in cells: Set<GridCoord>) -> Bool {
        var remaining = cells
        remaining.remove(cell)
        guard let start = remaining.first else { return true }
        var seen: Set<GridCoord> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            for (dx, dy) in GridCoord.cardinals {
                let next = current.neighbor(dx: dx, dy: dy)
                guard remaining.contains(next), seen.insert(next).inserted else { continue }
                queue.append(next)
            }
        }
        return seen.count != remaining.count
    }

    /// L-shape from two overlapping rects.
    /// When `allowStretch` is true, arms may be long (up to ~2× maxSize).
    func makeOrganicLRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        allowStretch: Bool = true,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let longMax = allowStretch ? maxSize * 2 : maxSize
        let armW = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let armH = rng.nextInt(upperBound: longMax - minSize + 1) + minSize
        let crossW = rng.nextInt(upperBound: longMax - minSize + 1) + minSize
        let crossH = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize

        guard width > max(armW, crossW) + 2, height > max(armH, crossH) + 2 else { return [] }

        let maxOriginX = width - max(armW, crossW) - 1
        let maxOriginY = height - max(armH, crossH) - 1
        guard maxOriginX >= 1, maxOriginY >= 1 else { return [] }

        let x = rng.nextInt(upperBound: maxOriginX) + 1
        let y = rng.nextInt(upperBound: maxOriginY) + 1

        var cells = Set<GridCoord>()
        for row in y..<min(height - 1, y + armH) {
            for col in x..<min(width - 1, x + armW) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }

        // Attach the cross-bar at one of the four corners of the primary arm.
        let corner = rng.nextInt(upperBound: 4)
        let crossX: Int
        let crossY: Int
        switch corner {
        case 0: // top-left of primary
            crossX = x
            crossY = y
        case 1: // top-right
            crossX = max(1, x + armW - crossW)
            crossY = y
        case 2: // bottom-left
            crossX = x
            crossY = max(1, y + armH - crossH)
        default: // bottom-right
            crossX = max(1, x + armW - crossW)
            crossY = max(1, y + armH - crossH)
        }

        for row in crossY..<min(height - 1, crossY + crossH) {
            for col in crossX..<min(width - 1, crossX + crossW) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }

        return cells
    }

    func centroid(of cells: Set<GridCoord>) -> GridCoord {
        let sum = cells.reduce((x: 0, y: 0)) { partial, cell in
            (partial.x + cell.x, partial.y + cell.y)
        }
        let count = max(cells.count, 1)
        return GridCoord(x: sum.x / count, y: sum.y / count, story: 0)
    }

    func spawnCell(for room: GeneratedRoom) -> GridCoord {
        guard let nearest = room.cells.min(by: { a, b in
            let da = abs(a.x - room.center.x) + abs(a.y - room.center.y)
            let db = abs(b.x - room.center.x) + abs(b.y - room.center.y)
            return da < db
        }) else {
            return room.center
        }
        return nearest
    }

    func carveRooms(_ rooms: [GeneratedRoom], into story: inout [[Tile]]) {
        for room in rooms {
            for cell in room.cells {
                story[cell.y][cell.x] = Tile(kind: .floor(isPit: false))
            }
        }
    }

    func topRightRoom(from rooms: [GeneratedRoom]) -> GeneratedRoom {
        rooms.max { lhs, rhs in
            let lhsScore = (lhs.center.x - lhs.center.y, -(lhs.center.x + lhs.center.y))
            let rhsScore = (rhs.center.x - rhs.center.y, -(rhs.center.x + rhs.center.y))
            return lhsScore < rhsScore
        } ?? rooms[0]
    }

    func runRoomsPass(state: inout GenerationAttemptState, config: WorldGenerationConfig) {
        let params = config.generation
        state.tiles = filledWalls(
            width: state.width,
            height: state.height,
            stories: state.stories
        )
        state.rooms = placePackedRooms(
            count: params.roomCount,
            minSize: params.room.minRoomSize,
            maxSize: params.room.maxRoomSize,
            shape: params.room.shape,
            width: state.width,
            height: state.height,
            rng: &state.rng
        )
        carveRooms(state.rooms, into: &state.tiles[0])
    }
}
