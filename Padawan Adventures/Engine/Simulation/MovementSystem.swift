import CoreGraphics
import Foundation

struct FractionalGridPose: Equatable, Sendable {
    var x: Double
    var y: Double
    var story: Int
}

struct MovementSystem: Sendable {
    /// Default walking speed in tiles per second.
    static let defaultTilesPerSecond: Double = 1.0
    /// Multiplier applied while descending a slide.
    static let slideDescentSpeedMultiplier: Double = 2.0

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
    /// Continuous segment start; nil means use integer `segmentStart` centers.
    private var segmentOriginX: Double?
    private var segmentOriginY: Double?

    init(tilesPerSecond: Double = MovementSystem.defaultTilesPerSecond) {
        self.tilesPerSecond = max(tilesPerSecond, 0.000_001)
    }

    mutating func begin(path: [GridCoord]) {
        guard path.count >= 2 else {
            reset()
            return
        }

        let preserved = isMoving ? fractionalPosition() : nil

        self.path = path
        pathIndex = 0
        segmentStart = path[0]
        segmentEnd = path[1]
        segmentProgress = 0
        occupancyCommitted = false
        isMoving = true

        if let preserved {
            // Bridge from the current visual pose to the first waypoint.
            segmentOriginX = preserved.x
            segmentOriginY = preserved.y
        } else {
            clearSegmentOrigin()
        }
    }

    mutating func reset() {
        path = []
        pathIndex = 0
        segmentStart = nil
        segmentEnd = nil
        segmentProgress = 0
        occupancyCommitted = false
        isMoving = false
        clearSegmentOrigin()
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
            let segmentLength = activeSegmentLength(to: currentEnd, logicalStart: currentStart)
            let speed = tilesPerSecond * speedMultiplier(from: currentStart, to: currentEnd, in: world)
            let segmentDuration = segmentLength / speed
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

    /// Continuous screen-space feet position along the active segment.
    func interpolatedScreenPosition(
        in world: GameWorld,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        guard isMoving, let start = segmentStart, let end = segmentEnd else {
            let coord = world.playerPosition ?? world.spawn
            return IsometricMath.entityScreenPosition(coord, config: config)
        }

        if isVerticalLadderSegment(from: start, to: end) {
            let from = IsometricMath.entityScreenPosition(start, config: config)
            let to = IsometricMath.entityScreenPosition(end, config: config)
            let t = segmentProgress
            return CGPoint(
                x: from.x + (to.x - from.x) * t,
                y: from.y + (to.y - from.y) * t
            )
        }

        let pose = fractionalPosition()
        return IsometricMath.entityScreenPosition(
            x: pose.x,
            y: pose.y,
            story: pose.story,
            config: config
        )
    }

    func fractionalPosition() -> FractionalGridPose {
        guard let start = segmentStart, let end = segmentEnd else {
            return FractionalGridPose(x: 0, y: 0, story: 0)
        }

        let originX = segmentOriginX ?? Double(start.x)
        let originY = segmentOriginY ?? Double(start.y)
        let t = segmentProgress
        let story = t < 0.5 ? start.story : end.story
        return FractionalGridPose(
            x: originX + (Double(end.x) - originX) * t,
            y: originY + (Double(end.y) - originY) * t,
            story: story
        )
    }

    func totalDuration(for path: [GridCoord], in world: GameWorld? = nil) -> TimeInterval {
        guard path.count >= 2 else { return 0 }
        var total: Double = 0
        for index in 0..<(path.count - 1) {
            let start = path[index]
            let end = path[index + 1]
            let multiplier = world.map { speedMultiplier(from: start, to: end, in: $0) } ?? 1.0
            total += segmentDistance(from: start, to: end) / (tilesPerSecond * multiplier)
        }
        return total
    }

    /// Same tile xy, different story — ladder transit.
    static func isVerticalLadderSegment(from start: GridCoord, to end: GridCoord) -> Bool {
        start.x == end.x && start.y == end.y && start.story != end.story
    }

    private func isVerticalLadderSegment(from start: GridCoord, to end: GridCoord) -> Bool {
        Self.isVerticalLadderSegment(from: start, to: end)
    }

    /// Slide tiles only speed up when moving to a lower story.
    private func speedMultiplier(from start: GridCoord, to end: GridCoord, in world: GameWorld) -> Double {
        guard end.story < start.story,
              case .slide = world.tile(at: start)?.kind else {
            return 1.0
        }
        return Self.slideDescentSpeedMultiplier
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
        clearSegmentOrigin()

        if pathIndex >= path.count - 1 {
            reset()
            return
        }

        segmentStart = path[pathIndex]
        segmentEnd = path[pathIndex + 1]
    }

    private mutating func clearSegmentOrigin() {
        segmentOriginX = nil
        segmentOriginY = nil
    }

    private func activeSegmentLength(to end: GridCoord, logicalStart: GridCoord) -> Double {
        let originX = segmentOriginX ?? Double(logicalStart.x)
        let originY = segmentOriginY ?? Double(logicalStart.y)
        let dx = Double(end.x) - originX
        let dy = Double(end.y) - originY
        if dx != 0 || dy != 0 {
            return hypot(dx, dy)
        }
        if logicalStart.story != end.story {
            return 1.0
        }
        return 0
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
