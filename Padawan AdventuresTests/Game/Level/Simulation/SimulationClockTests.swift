import Foundation
import Testing
@testable import Padawan_Adventures

struct SimulationClockTests {
    @Test func tickDurationIs15fps() {
        #expect(abs(SimulationClock.tickDuration - (1.0 / 15.0)) < 0.000_001)
    }

    @Test func advanceEmitsTicksAtRate() {
        var clock = SimulationClock()
        clock.maxCatchUpTicks = 20
        clock.maxFrameDelta = 1.0
        let ticks = clock.advance(deltaTime: 1.0)
        #expect(ticks == 15)
    }

    @Test func accumulatorCarriesRemainder() {
        var clock = SimulationClock()
        let first = clock.advance(deltaTime: SimulationClock.tickDuration * 1.5)
        #expect(first == 1)

        let second = clock.advance(deltaTime: SimulationClock.tickDuration * 0.6)
        #expect(second == 1)
    }

    @Test func catchUpIsCapped() {
        var clock = SimulationClock()
        clock.maxCatchUpTicks = 5
        clock.maxFrameDelta = 10.0
        let ticks = clock.advance(deltaTime: 10.0)
        #expect(ticks == 5)
    }
}
