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
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> [GeneratedRoom] {
        var rooms: [GeneratedRoom] = []
        var occupied = Set<GridCoord>()
        let attemptsPerRoom = 24

        while rooms.count < count {
            var placed = false
            for attempt in 0..<attemptsPerRoom {
                let cap = max(minSize, maxSize - (maxSize - minSize) * attempt / attemptsPerRoom)
                let raw: Set<GridCoord>
                if rng.nextBool(probability: 0.55) {
                    raw = makeOrganicLRoom(
                        minSize: minSize,
                        maxSize: cap,
                        width: width,
                        height: height,
                        rng: &rng
                    )
                } else {
                    raw = makeOrganicRectRoom(
                        minSize: minSize,
                        maxSize: cap,
                        width: width,
                        height: height,
                        rng: &rng
                    )
                }
                let shape = normalizeShape(raw)
                guard !shape.isEmpty else { continue }

                let cells: Set<GridCoord>?
                if rooms.isEmpty {
                    cells = firstOriginPlacement(
                        shape: shape,
                        occupied: occupied,
                        width: width,
                        height: height,
                        rng: &rng
                    )
                } else {
                    var found: Set<GridCoord>?
                    let anchors = rooms.shuffled(using: &rng).prefix(3)
                    for anchor in anchors {
                        if let placement = firstLegalPlacement(
                            shape: shape,
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
            .prefix(8)
        let shapeCells = shape.shuffled(using: &rng).prefix(8)
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

    func makeOrganicRectRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let w = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        let h = rng.nextInt(upperBound: maxSize - minSize + 1) + minSize
        // Occasional long corridor-like rooms.
        let stretch = rng.nextBool(probability: 0.25)
        let finalW = stretch && rng.nextBool(probability: 0.5) ? min(width - 2, w + maxSize) : w
        let finalH = stretch && finalW == w ? min(height - 2, h + maxSize) : h
        guard width > finalW + 2, height > finalH + 2 else { return [] }

        let x = rng.nextInt(upperBound: width - finalW - 1) + 1
        let y = rng.nextInt(upperBound: height - finalH - 1) + 1

        var cells = Set<GridCoord>()
        for row in y..<(y + finalH) {
            for col in x..<(x + finalW) {
                cells.insert(GridCoord(x: col, y: row, story: 0))
            }
        }
        return cells
    }

    /// L-shape from two overlapping rects; arms may be long (up to ~2× maxSize).
    func makeOrganicLRoom(
        minSize: Int,
        maxSize: Int,
        width: Int,
        height: Int,
        rng: inout SeededGenerator
    ) -> Set<GridCoord> {
        let longMax = maxSize * 2
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
            width: state.width,
            height: state.height,
            rng: &state.rng
        )
        carveRooms(state.rooms, into: &state.tiles[0])
    }
}
