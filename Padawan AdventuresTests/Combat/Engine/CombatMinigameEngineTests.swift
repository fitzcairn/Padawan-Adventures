import Foundation
import Testing
@testable import Padawan_Adventures

struct CombatMinigameEngineTests {
    private func makeEngine(
        timer: Double = 10,
        interval: Double = 1.0,
        travel: Double = 1.5,
        starsToWin: Int = 10,
        seed: UInt64 = 42
    ) -> CombatMinigameEngine {
        var engine = CombatMinigameEngine(
            config: .init(
                combatTimerSeconds: timer,
                shotIntervalSeconds: interval,
                shotTravelSeconds: travel,
                starsToWin: starsToWin
            ),
            rng: CombatSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    private func firstSpawnedShotID(in events: [CombatEngineEvent]) -> UUID? {
        for event in events {
            if case let .spawnShot(id, _) = event {
                return id
            }
        }
        return nil
    }

    @Test func constructsInactive() {
        let engine = CombatMinigameEngine(
            config: .init(
                combatTimerSeconds: 10,
                shotIntervalSeconds: 1,
                shotTravelSeconds: 1,
                starsToWin: 10
            )
        )
        #expect(!engine.isActive)
    }

    @Test func beginAndEndToggleActive() {
        var engine = makeEngine()
        #expect(engine.isActive)
        engine.end()
        #expect(!engine.isActive)
    }

    @Test func timerExpiryProducesLost() {
        var engine = makeEngine(timer: 2, interval: 100)
        _ = engine.tick(dt: 1.0)
        #expect(engine.outcome == nil)
        let events = engine.tick(dt: 1.1)
        #expect(events.contains(.lost))
        #expect(engine.outcome == .lost)
        #expect(engine.isFrozen)
    }

    @Test func slashHitsAwardStarsAndWin() {
        var engine = makeEngine(timer: 10, interval: 0.01, travel: 1.5, starsToWin: 3, seed: 1)
        var spawned: UUID?
        for _ in 0..<50 {
            let events = engine.tick(dt: 0.05)
            if let id = firstSpawnedShotID(in: events) {
                spawned = id
                break
            }
        }
        #expect(spawned != nil)

        let hit = engine.registerSlashHit(shotID: spawned!)
        #expect(hit)
        #expect(engine.combatStars == 1)

        while engine.combatStars < 3, engine.outcome == nil {
            let events = engine.tick(dt: 0.05)
            for event in events {
                if case let .spawnShot(id, _) = event {
                    _ = engine.registerSlashHit(shotID: id)
                }
            }
        }
        #expect(engine.outcome == CombatOutcome.won(starsAwarded: 3))
        #expect(engine.isFrozen)
    }

    @Test func spawnIntervalStaysWithinJitterBounds() {
        var delays: [Double] = []
        for seed in UInt64(1)...UInt64(20) {
            var e = CombatMinigameEngine(
                config: .init(
                    combatTimerSeconds: 30,
                    shotIntervalSeconds: 2.0,
                    shotTravelSeconds: 1,
                    starsToWin: 99
                ),
                rng: CombatSeededGenerator(seed: seed)
            )
            delays.append(e.scheduleNextSpawnDelay())
        }
        for delay in delays {
            #expect(delay >= 2.0 * 0.5 - 1e-9)
            #expect(delay <= 2.0 * 1.5 + 1e-9)
        }
        #expect(Set(delays.map { Int($0 * 1000) }).count > 1)
    }

    @Test func timerTickEventsInLastFiveSeconds() {
        var engine = makeEngine(timer: 6, interval: 100)
        var tickCount = 0
        for _ in 0..<30 {
            let events = engine.tick(dt: 0.25)
            tickCount += events.filter { $0 == .timerTick }.count
            if engine.outcome != nil { break }
        }
        #expect(tickCount >= 5)
    }

    @Test func impactRemovesShotWithoutStar() {
        var engine = makeEngine(timer: 10, interval: 0.01, travel: 1.5, starsToWin: 10, seed: 7)
        var shotID: UUID?
        for _ in 0..<40 {
            let events = engine.tick(dt: 0.05)
            if let id = firstSpawnedShotID(in: events) {
                shotID = id
                break
            }
        }
        #expect(shotID != nil)
        let impacted = engine.registerImpact(shotID: shotID!)
        #expect(impacted)
        #expect(engine.combatStars == 0)
        #expect(engine.shots[shotID!] == nil)
    }
}

/// Deterministic RNG for combat scheduling tests.
struct CombatSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEAD_BEEF : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
