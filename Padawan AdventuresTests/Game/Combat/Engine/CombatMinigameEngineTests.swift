import Foundation
import Testing
@testable import Padawan_Adventures

struct CombatMinigameEngineTests {
    private func makeEngine(
        travel: Double = 1.5,
        starsToWin: Int = 10,
        shotLetters: [String] = ["A", "B", "C"],
        graphemeSoundRepeatSeconds: Double = 3,
        minDecoy: Int = 2,
        maxDecoy: Int = 4,
        startingHealth: Int = 3,
        seed: UInt64 = 42
    ) -> CombatMinigameEngine {
        var engine = CombatMinigameEngine(
            config: .init(
                shotTravelSeconds: travel,
                starsToWin: starsToWin,
                shotLetters: shotLetters,
                graphemeSoundRepeatSeconds: graphemeSoundRepeatSeconds,
                minDecoyCount: minDecoy,
                maxDecoyCount: maxDecoy
            ),
            startingHealth: startingHealth,
            rng: CombatSeededGenerator(seed: seed)
        )
        engine.begin()
        return engine
    }

    /// Ticks until the next `.spawnWave` and returns its shots (and target).
    private func nextWave(
        _ engine: inout CombatMinigameEngine,
        maxTicks: Int = 200
    ) -> (target: String, shots: [CombatWaveShot])? {
        for _ in 0..<maxTicks {
            for event in engine.tick(dt: 0.05) {
                if case let .spawnWave(target, shots) = event {
                    return (target, shots)
                }
            }
        }
        return nil
    }

    @Test func constructsInactive() {
        let engine = CombatMinigameEngine(
            config: .init(
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

    @Test func combatLetterCaseBuildsPools() {
        #expect(CombatGraphemeCase.lower.shotLetterPool(from: ["A", "b", "C"]) == ["a", "b", "c"])
        #expect(CombatGraphemeCase.upper.shotLetterPool(from: ["a", "B"]) == ["A", "B"])
        #expect(CombatGraphemeCase.both.shotLetterPool(from: ["a", "B"]) == ["a", "A", "b", "B"])
    }

    @Test func configAppliesDecoyClampsAndLetterCase() {
        let type = EnemyTypeConfig(
            letter: "E",
            color: "#FF0000",
            tilesPerSecond: 1,
            forgetSeconds: 3,
            shotPacingSeconds: 10,
            shotTravelSeconds: 3.2,
            starsToWin: 5
        )
        let config = CombatMinigameEngine.Config(
            from: type,
            minDecoyCount: 0,
            maxDecoyCount: 2,
            graphemeCase: .lower
        )
        #expect(config.shotLetters == ["a", "i", "n", "p", "s", "t"])
        #expect(config.minDecoyCount == 1)
        #expect(config.maxDecoyCount == 2)

        let both = CombatMinigameEngine.Config(from: type, graphemeCase: .both)
        #expect(both.shotLetters == [
            "a", "A", "i", "I", "n", "N", "p", "P", "s", "S", "t", "T",
        ])
    }

    @Test func waveCompositionHasOneTargetAndValidDecoys() throws {
        var engine = makeEngine(minDecoy: 2, maxDecoy: 4, seed: 11)
        let wave = try #require(nextWave(&engine))
        let targets = wave.shots.filter(\.isTarget)
        let decoys = wave.shots.filter { !$0.isTarget }
        #expect(targets.count == 1)
        #expect(targets[0].letter == wave.target)
        #expect((2...4).contains(decoys.count))
        for decoy in decoys {
            #expect(decoy.letter != wave.target)
            #expect(["A", "B", "C"].contains(decoy.letter))
        }
        for shot in wave.shots {
            #expect(["A", "B", "C"].contains(shot.letter))
        }
    }

    @Test func speedJitterAndLaneIndicesAreValid() throws {
        var engine = makeEngine(minDecoy: 3, maxDecoy: 3, seed: 5)
        let wave = try #require(nextWave(&engine))
        for shot in wave.shots {
            #expect(shot.speedJitter >= 0.9 - 1e-9)
            #expect(shot.speedJitter <= 1.1 + 1e-9)
        }
        let lanes = wave.shots.map(\.laneIndex).sorted()
        #expect(lanes == Array(0..<wave.shots.count))
    }

    @Test func singleLetterPoolProducesSoloWave() throws {
        var engine = makeEngine(shotLetters: ["A"], minDecoy: 2, maxDecoy: 4, seed: 1)
        let wave = try #require(nextWave(&engine))
        #expect(wave.shots.count == 1)
        #expect(wave.shots[0].isTarget)
        #expect(wave.shots[0].letter == "A")
    }

    @Test func correctSlashAwardsStarAndResolves() throws {
        var engine = makeEngine(starsToWin: 99, seed: 7)
        let wave = try #require(nextWave(&engine))
        let targetID = try #require(wave.shots.first(where: \.isTarget)?.id)
        #expect(engine.registerSlashHit(shotID: targetID) == .correct)
        #expect(engine.combatStars == 1)
        #expect(engine.wavePhase == .resolving)
        #expect(engine.registerSlashHit(shotID: targetID) == .ignored)
    }

    @Test func wrongSlashCostsOneHeartAndNoStars() throws {
        var engine = makeEngine(starsToWin: 99, startingHealth: 3, seed: 9)
        let wave = try #require(nextWave(&engine))
        let decoyID = try #require(wave.shots.first(where: { !$0.isTarget })?.id)
        #expect(engine.registerSlashHit(shotID: decoyID) == .wrong)
        #expect(engine.combatStars == 0)
        #expect(engine.healthCount == 2)
        #expect(engine.wavePhase == .resolving)
    }

    @Test func impactCostsExactlyOneHeartPerWave() throws {
        var engine = makeEngine(starsToWin: 99, startingHealth: 3, seed: 13)
        let wave = try #require(nextWave(&engine))
        #expect(wave.shots.count >= 2)
        let first = wave.shots[0].id
        let second = wave.shots[1].id
        let firstDamaged = engine.registerWaveImpact(shotID: first)
        #expect(firstDamaged)
        #expect(engine.healthCount == 2)
        let secondDamaged = engine.registerWaveImpact(shotID: second)
        #expect(!secondDamaged)
        #expect(engine.healthCount == 2)
        #expect(engine.wavePhase == .resolving)
    }

    @Test func deferredLostEmittedFromFinishWaveResolution() throws {
        var engine = makeEngine(starsToWin: 99, startingHealth: 1, seed: 15)
        let wave = try #require(nextWave(&engine))
        let decoyID = try #require(wave.shots.first(where: { !$0.isTarget })?.id)
        #expect(engine.registerSlashHit(shotID: decoyID) == .wrong)
        #expect(engine.outcome == .lost)

        for _ in 0..<20 {
            let events = engine.tick(dt: 0.05)
            #expect(!events.contains(.lost))
        }

        let finishing = engine.finishWaveResolution()
        #expect(finishing.contains(.healthChanged(0)))
        #expect(finishing.contains(.lost))
    }

    @Test func deferredWonEmittedFromFinishWaveResolution() throws {
        var engine = makeEngine(starsToWin: 1, seed: 17)
        let wave = try #require(nextWave(&engine))
        let targetID = try #require(wave.shots.first(where: \.isTarget)?.id)
        #expect(engine.registerSlashHit(shotID: targetID) == .correct)
        #expect(engine.outcome == MinigameOutcome.won(starsAwarded: 1))

        for _ in 0..<20 {
            let events = engine.tick(dt: 0.05)
            #expect(!events.contains(.won))
        }

        let finishing = engine.finishWaveResolution()
        #expect(finishing.contains(.won))
    }

    @Test func nextWaveSpawnsAfterGapWithDifferentTarget() throws {
        var engine = makeEngine(starsToWin: 99, seed: 21)
        let first = try #require(nextWave(&engine))
        let targetID = try #require(first.shots.first(where: \.isTarget)?.id)
        #expect(engine.registerSlashHit(shotID: targetID) == .correct)
        _ = engine.finishWaveResolution()

        let second = try #require(nextWave(&engine))
        #expect(second.target != first.target)
    }

    @Test func sequenceCueReplaysOnLetterSoundInterval() throws {
        var engine = makeEngine(
            starsToWin: 99,
            graphemeSoundRepeatSeconds: 3,
            seed: 1
        )
        let wave = try #require(nextWave(&engine))
        var replayCount = 0
        for _ in 0..<70 {
            for event in engine.tick(dt: 0.1) {
                if case let .sequenceCue(letter) = event {
                    #expect(letter == wave.target)
                    replayCount += 1
                }
            }
        }
        #expect(replayCount >= 2)
    }

    @Test func correctSlashChangesCueToADifferentLetter() throws {
        var engine = makeEngine(
            starsToWin: 99,
            shotLetters: ["A", "B", "C"],
            seed: 21
        )
        let first = try #require(nextWave(&engine))
        let targetID = try #require(first.shots.first(where: \.isTarget)?.id)
        #expect(engine.registerSlashHit(shotID: targetID) == .correct)
        _ = engine.finishWaveResolution()
        let second = try #require(nextWave(&engine))
        #expect(second.target != first.target)
        #expect(engine.sequenceRequiredLetter == second.target)
    }

    @Test func clearingEveryWaveWins() throws {
        var engine = makeEngine(starsToWin: 3, seed: 9)
        while engine.outcome == nil {
            guard let wave = nextWave(&engine) else { break }
            let targetID = try #require(wave.shots.first(where: \.isTarget)?.id)
            #expect(engine.registerSlashHit(shotID: targetID) == .correct)
            for event in engine.finishWaveResolution() {
                if case .won = event { break }
            }
        }
        #expect(engine.outcome == MinigameOutcome.won(starsAwarded: 3))
        #expect(engine.isFrozen)
    }

    @Test func failingEveryWaveLoses() throws {
        var engine = makeEngine(starsToWin: 99, startingHealth: 2, seed: 7)
        while engine.outcome == nil {
            guard let wave = nextWave(&engine) else { break }
            let decoyID = try #require(wave.shots.first(where: { !$0.isTarget })?.id)
            #expect(engine.registerSlashHit(shotID: decoyID) == .wrong)
            _ = engine.finishWaveResolution()
        }
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
