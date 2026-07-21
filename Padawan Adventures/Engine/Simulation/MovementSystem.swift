import CoreGraphics
import Foundation

struct MovementSystem: Sendable {
    /// Default walking speed in tiles per second.
    static let defaultTilesPerSecond: Double = 1.0

    /// Current player movement speed in tiles per second. Mutable so gameplay events can change it.
    var tilesPerSecond: Double {
        didSet { tilesPerSecond = max(tilesPerSecond, 0.000_001) }
    }

    private(set) var path: [GridCoord] = []
    private(set) var pathIndex: Int = 0
    private(set) var segmentStart: GridCoord?
    private(set) var segmentEnd: GridCoord?
    private(set) var segmentProgress: Double = 0
    private(set) var isMoving: Bool = false
    /// Whether occupancy has been committed to `segmentEnd` for the current segment (at border cross).
    private var occupancyCommitted: Bool = false

    init(tilesPerSecond: Double = MovementSystem.defaultTilesPerSecond) {
        self.tilesPerSecond = max(tilesPerSecond, 0.000_001)
    }

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
        occupancyCommitted = false
        isMoving = true
    }

    mutating func reset() {
        path = []
        pathIndex = 0
        segmentStart = nil
        segmentEnd = nil
        segmentProgress = 0
        occupancyCommitted = false
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
        var currentStart = start
        var currentEnd = end

        while remaining > 0, isMoving {
            let segmentLength = segmentDistance(from: currentStart, to: currentEnd)
            let segmentDuration = segmentLength / tilesPerSecond
            guard segmentDuration > 0 else {
                commitOccupancyIfNeeded(end: currentEnd, world: &world, events: &events)
                if !isMoving { return events }
                advanceSegment()
                if let nextStart = segmentStart, let nextEnd = segmentEnd {
                    currentStart = nextStart
                    currentEnd = nextEnd
                }
                continue
            }

            // Commit occupancy when crossing the shared tile border (progress 0.5).
            if !occupancyCommitted {
                let timeToBorder = segmentDuration * (0.5 - segmentProgress)
                if remaining >= timeToBorder {
                    remaining -= timeToBorder
                    segmentProgress = 0.5
                    commitOccupancyIfNeeded(end: currentEnd, world: &world, events: &events)
                    if !isMoving { return events }
                    continue
                } else {
                    segmentProgress += remaining / segmentDuration
                    remaining = 0
                    break
                }
            }

            let timeLeftInSegment = segmentDuration * (1 - segmentProgress)
            if remaining >= timeLeftInSegment {
                remaining -= timeLeftInSegment
                segmentProgress = 1
                advanceSegment()
                if let nextStart = segmentStart, let nextEnd = segmentEnd {
                    currentStart = nextStart
                    currentEnd = nextEnd
                }
            } else {
                segmentProgress += remaining / segmentDuration
                remaining = 0
            }
        }

        return events
    }

    /// Continuous screen-space feet position between segment endpoints.
    func interpolatedScreenPosition(
        in world: GameWorld,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        guard isMoving,
              let start = segmentStart,
              let end = segmentEnd else {
            let coord = world.playerPosition ?? world.spawn
            return IsometricMath.entityScreenPosition(coord, config: config)
        }

        let from = IsometricMath.entityScreenPosition(start, config: config)
        let to = IsometricMath.entityScreenPosition(end, config: config)
        let t = segmentProgress
        return CGPoint(
            x: from.x + (to.x - from.x) * CGFloat(t),
            y: from.y + (to.y - from.y) * CGFloat(t)
        )
    }

    func totalDuration(for path: [GridCoord]) -> TimeInterval {
        guard path.count >= 2 else { return 0 }
        var total: Double = 0
        for index in 0..<(path.count - 1) {
            total += segmentDistance(from: path[index], to: path[index + 1]) / tilesPerSecond
        }
        return total
    }

    private mutating func commitOccupancyIfNeeded(
        end: GridCoord,
        world: inout GameWorld,
        events: inout [MovementEvent]
    ) {
        guard !occupancyCommitted else { return }
        occupancyCommitted = true
        world.setPlayerPosition(end)
        events.append(.reached(end))

        if world.tile(at: end)?.isPit == true {
            let resolution = world.resolvePit(at: end)
            events.append(.pit(resolution))
            if case .hazard = resolution {
                reset()
                return
            }
            if case .fell(let lower) = resolution {
                events.append(.reached(lower))
            }
        }
    }

    private mutating func advanceSegment() {
        pathIndex += 1
        segmentProgress = 0
        occupancyCommitted = false

        if pathIndex >= path.count - 1 {
            reset()
            return
        }

        segmentStart = path[pathIndex]
        segmentEnd = path[pathIndex + 1]
    }

    private func segmentDistance(from start: GridCoord, to end: GridCoord) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx != 0 || dy != 0 {
            return hypot(Double(dx), Double(dy))
        }
        return 1.0
    }
}

enum MovementEvent: Equatable, Sendable {
    case reached(GridCoord)
    case pit(PitResolution)
}
