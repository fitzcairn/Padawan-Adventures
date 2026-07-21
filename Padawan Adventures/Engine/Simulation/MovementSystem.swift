import Foundation

struct MovementSystem: Sendable {
    static let tilesPerSecond: Double = 0.2

    private(set) var path: [GridCoord] = []
    private(set) var pathIndex: Int = 0
    private(set) var segmentStart: GridCoord?
    private(set) var segmentEnd: GridCoord?
    private(set) var segmentProgress: Double = 0
    private(set) var isMoving: Bool = false

    mutating func begin(path: [GridCoord]) {
        guard path.count >= 2 else {
            reset()
            return
        }
        self.path = path
        pathIndex = 0
        segmentStart = path[0]
        segmentEnd = path[1]
        segmentProgress = 0
        isMoving = true
    }

    mutating func reset() {
        path = []
        pathIndex = 0
        segmentStart = nil
        segmentEnd = nil
        segmentProgress = 0
        isMoving = false
    }

    /// Advances movement by `deltaTime` seconds. Returns events triggered this frame.
    mutating func update(deltaTime: TimeInterval, world: inout GameWorld) -> [MovementEvent] {
        guard isMoving,
              let start = segmentStart,
              let end = segmentEnd else {
            return []
        }

        var events: [MovementEvent] = []
        var remaining = deltaTime

        while remaining > 0, isMoving {
            let segmentLength = segmentDistance(from: start, to: end)
            let segmentDuration = segmentLength / Self.tilesPerSecond
            let timeLeftInSegment = segmentDuration * (1 - segmentProgress)

            if remaining >= timeLeftInSegment {
                remaining -= timeLeftInSegment
                world.setPlayerPosition(end)
                events.append(.reached(end))

                if world.tile(at: end)?.isPit == true {
                    let resolution = world.resolvePit(at: end)
                    events.append(.pit(resolution))
                    if case .hazard = resolution {
                        reset()
                        return events
                    }
                    if case .fell(let lower) = resolution {
                        events.append(.reached(lower))
                    }
                }

                advanceSegment()
            } else {
                segmentProgress += remaining / segmentDuration
                remaining = 0
            }
        }

        return events
    }

    func interpolatedPosition(in world: GameWorld) -> GridCoord {
        guard isMoving,
              let start = segmentStart,
              let end = segmentEnd else {
            return world.playerPosition ?? world.spawn
        }

        let t = segmentProgress
        return GridCoord(
            x: lerp(start.x, end.x, t),
            y: lerp(start.y, end.y, t),
            story: t < 0.5 ? start.story : end.story
        )
    }

    func totalDuration(for path: [GridCoord]) -> TimeInterval {
        guard path.count >= 2 else { return 0 }
        var total: Double = 0
        for index in 0..<(path.count - 1) {
            total += segmentDistance(from: path[index], to: path[index + 1]) / Self.tilesPerSecond
        }
        return total
    }

    private mutating func advanceSegment() {
        pathIndex += 1
        segmentProgress = 0

        if pathIndex >= path.count - 1 {
            reset()
            return
        }

        segmentStart = path[pathIndex]
        segmentEnd = path[pathIndex + 1]
    }

    private func segmentDistance(from start: GridCoord, to end: GridCoord) -> Double {
        if start.x != end.x || start.y != end.y {
            return Double(abs(start.x - end.x) + abs(start.y - end.y))
        }
        return 1.0
    }

    private func lerp(_ a: Int, _ b: Int, _ t: Double) -> Int {
        Int((Double(a) + (Double(b - a) * t)).rounded())
    }
}

enum MovementEvent: Equatable, Sendable {
    case reached(GridCoord)
    case pit(PitResolution)
}
