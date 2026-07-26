import CoreGraphics
import Foundation

struct FractionalGridPose: Equatable, Sendable {
    var x: Double
    var y: Double
    var story: Int
}

struct MovementSystem: Sendable {
    /// Default walking speed in tiles per second.
    static let defaultTilesPerSecond: Double = 2.0

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

    /// Follow `newPath` without snapping. If already mid-segment toward a waypoint that
    /// still appears on the new path, keep that segment's progress and only replace the suffix.
    /// Otherwise bridges from the current fractional pose via `begin`.
    mutating func retarget(path newPath: [GridCoord]) {
        guard newPath.count >= 2 else { return }

        if isMoving,
           let start = segmentStart,
           let end = segmentEnd,
           let endIndex = newPath.firstIndex(of: end) {
            var rebuilt = [start, end]
            let next = newPath.index(after: endIndex)
            if next < newPath.endIndex {
                rebuilt.append(contentsOf: newPath[next...])
            }
            path = rebuilt
            pathIndex = 0
            // Intentionally keep segmentProgress / occupancyCommitted / segmentOrigin.
            return
        }

        begin(path: newPath)
    }

    /// Complete the current tile step then stop — no mid-tile snap to occupancy center.
    mutating func finishCurrentSegmentAndStop() {
        guard isMoving, let start = segmentStart, let end = segmentEnd else {
            reset()
            return
        }
        path = [start, end]
        pathIndex = 0
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
        guard let playerID = world.entities.first(where: \.isPlayer)?.id else {
            return []
        }
        return update(deltaTime: deltaTime, world: &world, entityID: playerID)
    }

    /// Advances movement for a specific entity by `deltaTime` seconds.
    mutating func update(
        deltaTime: TimeInterval,
        world: inout GameWorld,
        entityID: UUID
    ) -> [MovementEvent] {
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
            let segmentDuration = segmentLength / tilesPerSecond
            guard segmentDuration > 0 else {
                commitOccupancyIfNeeded(end: currentEnd, world: &world, entityID: entityID, events: &events)
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
                    commitOccupancyIfNeeded(end: currentEnd, world: &world, entityID: entityID, events: &events)
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
        let fallback = world.playerPosition ?? world.spawn
        return interpolatedScreenPosition(in: world, entityID: nil, fallback: fallback, config: config)
    }

    func interpolatedScreenPosition(
        in world: GameWorld,
        entityID: UUID,
        config: IsometricConfig = IsometricConfig()
    ) -> CGPoint {
        let fallback = world.entity(id: entityID)?.position ?? world.spawn
        return interpolatedScreenPosition(in: world, entityID: entityID, fallback: fallback, config: config)
    }

    private func interpolatedScreenPosition(
        in world: GameWorld,
        entityID: UUID?,
        fallback: GridCoord,
        config: IsometricConfig
    ) -> CGPoint {
        guard isMoving, segmentStart != nil, segmentEnd != nil else {
            let coord = entityID.flatMap { world.entity(id: $0)?.position } ?? fallback
            return IsometricMath.entityScreenPosition(coord, config: config)
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
        entityID: UUID,
        events: inout [MovementEvent]
    ) {
        guard !occupancyCommitted else { return }
        occupancyCommitted = true
        world.setEntityPosition(end, id: entityID)
        events.append(.reached(end))

        let isPlayer = world.entity(id: entityID)?.isPlayer == true
        guard isPlayer, let tile = world.tile(at: end) else { return }

        if tile.isPit {
            let resolution = world.resolvePit(at: end)
            let approach = segmentStart ?? end
            events.append(.pit(resolution: resolution, approach: approach))
            reset()
            return
        }
        if tile.isGate {
            let approach = segmentStart ?? end
            events.append(.gate(gate: end, approach: approach))
            reset()
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
    /// `approach` is the floor tile the player walked from (timeout retreat).
    case pit(resolution: PitResolution, approach: GridCoord)
    /// `gate` is the occupied gate tile; `approach` is the floor tile the player walked from.
    case gate(gate: GridCoord, approach: GridCoord)
}
