import Foundation
import Testing
@testable import Padawan_Adventures

struct CombatMinigameEngineTests {
    private func makeEngine(
        timer: Double = 10,
        travel: Double = 1.5,
        starsToWin: Int = 10,
        shotLetters: [String] = ["A", "B", "C"],
        meanInterval: Double? = 0.01,
        letterSoundRepeatSeconds: Double = 3,
        startingHealth: Int = 3,
        seed: UInt64 = 42
    ) -> CombatMinigameEngine {
        var engine = CombatMinigameEngine(
            config: .init(
                combatTimerSeconds: timer,
                shotTravelSeconds: travel,
                starsToWin: starsToWin,
                shotLetters: shotLetters,
                meanShotIntervalSeconds: meanInterval,
                letterSoundRepeatSeconds: letterSoundRepeatSeconds
            ),
            startingHealth: startingHealth,
            rng: CombatSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    private func firstSpawnedShot(
        in events: [CombatEngineEvent]
    ) -> (id: UUID, visualLetter: String)? {
        for event in events {
            if case let .spawnShot(id, _, visualLetter) = event {
                return (id, visualLetter)
            }
        }
        return nil
    }

    @Test func constructsInactive() {
        let engine = CombatMinigameEngine(
            config: .init(
                combatTimerSeconds: 10,
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

    @Test func timerExpiryDoesNotProduceLost() {
        var engine = makeEngine(timer: 2, meanInterval: 100)
        _ = engine.tick(dt: 1.0)
        #expect(engine.outcome == nil)
        let events = engine.tick(dt: 1.1)
        #expect(!events.contains(.lost))
        #expect(engine.outcome == nil)
        #expect(!engine.isFrozen)
        #expect(engine.remainingTime == 0)
    }

    @Test func spawnsContinueAfterConfiguredTimerWindow() {
        // Old spawnWindowEnd was timer - travel (here 2). Spawns must continue past that.
        var engine = makeEngine(timer: 4, travel: 2, starsToWin: 99, meanInterval: 0.2, seed: 3)
        var spawnCountBeforeWindow = 0
        var spawnCountAfterWindow = 0
        for _ in 0..<80 {
            let events = engine.tick(dt: 0.1)
            let spawns = events.filter {
                if case .spawnShot = $0 { return true }
                return false
            }.count
            if engine.elapsed <= 2 {
                spawnCountBeforeWindow += spawns
            } else {
                spawnCountAfterWindow += spawns
            }
        }
        #expect(spawnCountBeforeWindow > 0)
        #expect(spawnCountAfterWindow > 0)
        #expect(engine.outcome == nil)
    }

    @Test func derivedIntervalSupportsWinWithFiftyPercentMisses() {
        let timer = 10.0
        let travel = 3.2
        let stars = 5
        let letters = ["A", "B", "C"]
        let interval = CombatMinigameEngine.Config.derivedMeanShotInterval(
            combatTimerSeconds: timer,
            shotTravelSeconds: travel,
            starsToWin: stars,
            shotLetterCount: letters.count
        )
        let spawnWindow = max(timer - travel, timer * 0.4)
        let expectedShots = spawnWindow / interval
        let expectedMatching = expectedShots / Double(letters.count)
        let expectedStarsAtHalfHitRate = expectedMatching * 0.5
        #expect(expectedStarsAtHalfHitRate + 0.01 >= Double(stars))
    }

    @Test func configFromEnemyTypeDerivesInterval() {
        let type = EnemyTypeConfig(
            letter: "E",
            color: "#FF0000",
            tilesPerSecond: 1,
            forgetSeconds: 3,
            combatTimerSeconds: 10,
            shotTravelSeconds: 3.2,
            starsToWin: 5
        )
        let config = CombatMinigameEngine.Config(from: type)
        let expected = CombatMinigameEngine.Config.derivedMeanShotInterval(
            combatTimerSeconds: 10,
            shotTravelSeconds: 3.2,
            starsToWin: 5,
            shotLetterCount: 3
        )
        #expect(abs(config.meanShotIntervalSeconds - expected) < 1e-9)
    }

    @Test func configAppliesSpawnRateAndLetterCase() {
        let type = EnemyTypeConfig(
            letter: "E",
            color: "#FF0000",
            tilesPerSecond: 1,
            forgetSeconds: 3,
            combatTimerSeconds: 10,
            shotTravelSeconds: 3.2,
            starsToWin: 5
        )
        let config = CombatMinigameEngine.Config(
            from: type,
            letterSpawnRate: 0.7,
            letterCase: .lower
        )
        #expect(config.shotLetters == ["a", "b", "c"])
        let derived = CombatMinigameEngine.Config.derivedMeanShotInterval(
            combatTimerSeconds: 10,
            shotTravelSeconds: 3.2,
            starsToWin: 5,
            shotLetterCount: 3
        )
        #expect(abs(config.meanShotIntervalSeconds - derived / 0.7) < 1e-9)

        let both = CombatMinigameEngine.Config(from: type, letterCase: .both)
        #expect(both.shotLetters == ["a", "A", "b", "B", "c", "C"])
    }

    @Test func combatLetterCaseBuildsPools() {
        #expect(CombatLetterCase.lower.shotLetterPool(from: ["A", "b", "C"]) == ["a", "b", "c"])
        #expect(CombatLetterCase.upper.shotLetterPool(from: ["a", "B"]) == ["A", "B"])
        #expect(CombatLetterCase.both.shotLetterPool(from: ["a", "B"]) == ["a", "A", "b", "B"])
    }

    @Test func sequenceCueThenSpawnsShareRequiredLetter() {
        var engine = makeEngine(meanInterval: 0.01, seed: 11)
        var currentCue: String?
        var matchedSpawns = 0

        for _ in 0..<60 {
            let events = engine.tick(dt: 0.05)
            for event in events {
                if case let .sequenceCue(letter) = event {
                    currentCue = letter
                    matchedSpawns = 0
                }
                if case let .spawnShot(id, _, _) = event,
                   let shot = engine.shots[id] {
                    #expect(currentCue != nil)
                    #expect(shot.requiredLetter == currentCue)
                    matchedSpawns += 1
                }
            }
            if matchedSpawns >= 2 { break }
        }

        #expect(currentCue != nil)
        #expect(matchedSpawns >= 2)
    }

    @Test func visualLettersComeFromConfiguredAlphabet() {
        var engine = makeEngine(shotLetters: ["A", "B", "C"], meanInterval: 0.01, seed: 3)
        var visuals = Set<String>()
        for _ in 0..<80 {
            let events = engine.tick(dt: 0.05)
            for event in events {
                if case let .spawnShot(_, _, visual) = event {
                    visuals.insert(visual)
                }
            }
        }
        #expect(visuals.isSubset(of: ["A", "B", "C"]))
        #expect(visuals.count > 1)
    }

    @Test func cuedLetterSpawnsMoreOftenThanEachOtherLetter() {
        var engine = makeEngine(
            starsToWin: 99,
            shotLetters: ["A", "B", "C"],
            meanInterval: 0.01,
            seed: 17
        )
        // Establish a cue, then keep slashing only mismatches so the cue stays fixed.
        var cue: String?
        for _ in 0..<40 {
            for event in engine.tick(dt: 0.05) {
                if case let .sequenceCue(letter) = event {
                    cue = letter
                }
            }
            if cue != nil { break }
        }
        let required = try! #require(cue)

        var counts: [String: Int] = ["A": 0, "B": 0, "C": 0]
        for _ in 0..<400 {
            for event in engine.tick(dt: 0.05) {
                guard case let .spawnShot(id, _, visual) = event else { continue }
                counts[visual, default: 0] += 1
                if visual != required {
                    _ = engine.registerSlashHit(shotID: id)
                }
            }
        }

        let cuedCount = counts[required] ?? 0
        for letter in ["A", "B", "C"] where letter != required {
            #expect(cuedCount > (counts[letter] ?? 0))
        }
    }

    @Test func correctSlashIncreasesNetProgressAndWrongDecreasesIt() {
        var engine = makeEngine(starsToWin: 99, meanInterval: 0.01, seed: 5)
        var correctID: UUID?
        var wrongID: UUID?

        for _ in 0..<80 where correctID == nil || wrongID == nil {
            let events = engine.tick(dt: 0.05)
            for event in events {
                guard case let .spawnShot(id, _, _) = event,
                      let shot = engine.shots[id] else { continue }
                if shot.visualLetter == engine.sequenceRequiredLetter {
                    correctID = id
                } else {
                    wrongID = id
                }
            }
        }

        #expect(correctID != nil)
        #expect(wrongID != nil)

        #expect(engine.registerSlashHit(shotID: correctID!) == .correct)
        #expect(engine.combatStars == 1)

        #expect(engine.registerSlashHit(shotID: wrongID!) == .wrong)
        #expect(engine.combatStars == 0)
        #expect(engine.shots[wrongID!] == nil)
    }

    @Test func winRequiresNetProgressNotGrossCorrects() {
        var engine = makeEngine(starsToWin: 3, meanInterval: 0.01, seed: 9)

        func slashMatching(count: Int) {
            var done = 0
            while done < count, engine.outcome == nil {
                for event in engine.tick(dt: 0.05) {
                    guard case let .spawnShot(id, _, _) = event,
                          engine.matchesCurrentCue(shotID: id) else { continue }
                    #expect(engine.registerSlashHit(shotID: id) == .correct)
                    done += 1
                    if done >= count { break }
                }
            }
        }

        slashMatching(count: 2)
        #expect(engine.combatStars == 2)
        #expect(engine.outcome == nil)

        var wrongDone = false
        for _ in 0..<80 where !wrongDone {
            for event in engine.tick(dt: 0.05) {
                guard case let .spawnShot(id, _, _) = event,
                      let shot = engine.shots[id],
                      shot.visualLetter != engine.sequenceRequiredLetter else { continue }
                #expect(engine.registerSlashHit(shotID: id) == .wrong)
                wrongDone = true
                break
            }
        }
        #expect(wrongDone)
        #expect(engine.combatStars == 1)
        #expect(engine.outcome == nil)

        slashMatching(count: 2)
        #expect(engine.outcome == CombatOutcome.won(starsAwarded: 3))
    }

    @Test func onScreenShotBecomesCorrectWhenCueChangesToItsLetter() throws {
        var engine = makeEngine(
            starsToWin: 99,
            shotLetters: ["A", "B"],
            meanInterval: 0.01,
            seed: 8
        )
        var targetID: UUID?
        var targetVisual: String?

        for _ in 0..<80 {
            for event in engine.tick(dt: 0.05) {
                guard case let .spawnShot(id, _, visual) = event else { continue }
                guard visual != engine.sequenceRequiredLetter else { continue }
                targetID = id
                targetVisual = visual
            }
            if targetID != nil { break }
        }

        let livingID = try #require(targetID)
        let livingVisual = try #require(targetVisual)
        #expect(livingVisual != engine.sequenceRequiredLetter)
        #expect(engine.registerSlashHit(shotID: livingID) == .wrong)

        // Keep a second mismatch alive until the cue changes to its letter.
        targetID = nil
        targetVisual = nil
        for _ in 0..<80 {
            for event in engine.tick(dt: 0.05) {
                guard case let .spawnShot(id, _, visual) = event else { continue }
                guard visual != engine.sequenceRequiredLetter else { continue }
                targetID = id
                targetVisual = visual
            }
            if targetID != nil { break }
        }

        let pendingID = try #require(targetID)
        let pendingVisual = try #require(targetVisual)
        #expect(pendingVisual != engine.sequenceRequiredLetter)

        var becameCorrect = false
        for _ in 0..<500 {
            if engine.sequenceRequiredLetter == pendingVisual, engine.shots[pendingID] != nil {
                let starsBefore = engine.combatStars
                #expect(engine.registerSlashHit(shotID: pendingID) == .correct)
                #expect(engine.combatStars == starsBefore + 1)
                becameCorrect = true
                break
            }

            for event in engine.tick(dt: 0.05) {
                guard case let .spawnShot(spawnID, _, _) = event,
                      spawnID != pendingID,
                      engine.matchesCurrentCue(shotID: spawnID) else { continue }
                if engine.registerSlashHit(shotID: spawnID) == .correct {
                    _ = engine.drainPendingEvents()
                }
            }
        }

        #expect(becameCorrect)
    }

    @Test func correctSlashesCanWin() {
        var engine = makeEngine(starsToWin: 3, meanInterval: 0.01, seed: 9)
        while engine.combatStars < 3, engine.outcome == nil {
            let events = engine.tick(dt: 0.05)
            for event in events {
                guard case let .spawnShot(id, _, _) = event,
                      let shot = engine.shots[id] else { continue }
                if shot.visualLetter == engine.sequenceRequiredLetter {
                    _ = engine.registerSlashHit(shotID: id)
                }
            }
        }
        #expect(engine.outcome == CombatOutcome.won(starsAwarded: 3))
        #expect(engine.isFrozen)
    }

    @Test func correctSlashesRequiredStaysWithinJitterBounds() {
        var lengths: [Int] = []
        for seed in UInt64(1)...UInt64(40) {
            var e = CombatMinigameEngine(
                config: .init(
                    combatTimerSeconds: 30,
                    shotTravelSeconds: 1,
                    starsToWin: 99
                ),
                rng: CombatSeededGenerator(seed: seed)
            )
            lengths.append(e.scheduleCorrectSlashesRequired())
        }
        for length in lengths {
            #expect(length >= 1)
            #expect(length <= 5)
        }
        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        #expect(mean > 2.0 && mean < 4.5)
    }

    @Test func cueChangesAfterRequiredCorrectSlashes() {
        var engine = makeEngine(starsToWin: 99, meanInterval: 0.01, seed: 21)
        var firstCue: String?
        for _ in 0..<40 {
            let events = engine.tick(dt: 0.05)
            for event in events {
                if case let .sequenceCue(letter) = event {
                    firstCue = letter
                }
            }
            if firstCue != nil { break }
        }
        #expect(firstCue != nil)
        let needed = engine.correctSlashesRemainingInSequence
        #expect(needed >= 1)

        var correctDone = 0
        var sawNextCue = false
        for _ in 0..<200 where !sawNextCue {
            let events = engine.tick(dt: 0.05)
            for event in events {
                guard case let .spawnShot(id, _, _) = event,
                      engine.matchesCurrentCue(shotID: id),
                      correctDone < needed else { continue }
                let result = engine.registerSlashHit(shotID: id)
                #expect(result == .correct)
                correctDone += 1
                let pending = engine.drainPendingEvents()
                if correctDone == needed {
                    let hasCue = pending.contains { event in
                        if case .sequenceCue = event { return true }
                        return false
                    }
                    #expect(hasCue)
                    sawNextCue = true
                }
            }
        }
        #expect(sawNextCue)
        #expect(correctDone == needed)
    }

    @Test func spawnIntervalStaysWithinJitterBounds() {
        let base = 2.0
        var delays: [Double] = []
        for seed in UInt64(1)...UInt64(20) {
            var e = CombatMinigameEngine(
                config: .init(
                    combatTimerSeconds: 30,
                    shotTravelSeconds: 1,
                    starsToWin: 99,
                    meanShotIntervalSeconds: base
                ),
                rng: CombatSeededGenerator(seed: seed)
            )
            delays.append(e.scheduleNextSpawnDelay())
        }
        for delay in delays {
            #expect(delay >= base * 0.5 - 1e-9)
            #expect(delay <= base * 1.5 + 1e-9)
        }
        #expect(Set(delays.map { Int($0 * 1000) }).count > 1)
    }

    @Test func timerTickEventsInLastFiveSeconds() {
        var engine = makeEngine(timer: 6, meanInterval: 100)
        var tickCount = 0
        for _ in 0..<30 {
            let events = engine.tick(dt: 0.25)
            tickCount += events.filter { $0 == .timerTick }.count
            if engine.outcome != nil { break }
        }
        #expect(tickCount >= 5)
    }

    @Test func sequenceCueReplaysOnLetterSoundInterval() {
        var engine = makeEngine(
            timer: 20,
            starsToWin: 99,
            meanInterval: 0.01,
            letterSoundRepeatSeconds: 3,
            seed: 1
        )

        var firstCue: String?
        for _ in 0..<40 {
            let events = engine.tick(dt: 0.05)
            for event in events {
                if case let .sequenceCue(letter) = event {
                    firstCue = letter
                }
            }
            if firstCue != nil { break }
        }
        #expect(firstCue != nil)

        var replayCount = 0
        for _ in 0..<70 {
            let events = engine.tick(dt: 0.1)
            for event in events {
                if case let .sequenceCue(letter) = event {
                    #expect(letter == firstCue)
                    replayCount += 1
                }
            }
        }
        // ~7 seconds of post-cue time at 3s interval → at least two replays.
        #expect(replayCount >= 2)
    }

    @Test func impactRemovesShotWithoutStarAndDeductsHealth() throws {
        var engine = makeEngine(
            timer: 10,
            travel: 1.5,
            starsToWin: 10,
            meanInterval: 0.01,
            startingHealth: 3,
            seed: 7
        )
        var matchingID: UUID?
        var mismatchID: UUID?
        for _ in 0..<80 {
            let events = engine.tick(dt: 0.05)
            for event in events {
                guard case let .spawnShot(id, _, _) = event else { continue }
                if engine.matchesCurrentCue(shotID: id) {
                    matchingID = id
                } else {
                    mismatchID = id
                }
            }
            if matchingID != nil, mismatchID != nil { break }
        }
        let match = try #require(matchingID)
        let mismatch = try #require(mismatchID)

        let matchDamaged = engine.registerImpact(shotID: match)
        let mismatchDamaged = engine.registerImpact(shotID: mismatch)
        #expect(matchDamaged)
        #expect(!mismatchDamaged)
        #expect(engine.combatStars == 0)
        #expect(engine.healthCount == 2)
        #expect(engine.shots[match] == nil)
        #expect(engine.shots[mismatch] == nil)
        let pending = engine.drainPendingEvents()
        #expect(pending.contains(.healthChanged(2)))
    }

    @Test func matchingImpactsToZeroHealthLoseCombat() throws {
        var engine = makeEngine(starsToWin: 99, meanInterval: 0.01, startingHealth: 2, seed: 7)
        var hits = 0
        for _ in 0..<200 where engine.outcome == nil {
            let events = engine.tick(dt: 0.05)
            for event in events {
                guard case let .spawnShot(id, _, _) = event,
                      engine.matchesCurrentCue(shotID: id) else { continue }
                if engine.registerImpact(shotID: id) {
                    hits += 1
                }
            }
        }
        #expect(hits == 2)
        #expect(engine.healthCount == 0)
        #expect(engine.outcome == .lost)
        #expect(engine.isFrozen)
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
