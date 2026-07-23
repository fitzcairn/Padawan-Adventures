import Foundation

struct SimulationClock: Sendable {
    static let ticksPerSecond: Double = 15
    static var tickDuration: TimeInterval { 1.0 / ticksPerSecond }

    private(set) var tickCount: UInt64 = 0
    private var accumulator: TimeInterval = 0
    var maxCatchUpTicks: Int = 5
    var maxFrameDelta: TimeInterval = 0.25

    /// Accumulates wall time and returns how many discrete simulation ticks to run.
    mutating func advance(deltaTime: TimeInterval) -> Int {
        let clamped = min(max(deltaTime, 0), maxFrameDelta)
        accumulator += clamped

        var ticks = Int(accumulator / Self.tickDuration)
        if ticks > maxCatchUpTicks {
            ticks = maxCatchUpTicks
        }

        accumulator -= Double(ticks) * Self.tickDuration
        return ticks
    }

    mutating func registerTick() {
        tickCount += 1
    }

    var animationFrame: Int {
        Int(tickCount % 4)
    }
}
