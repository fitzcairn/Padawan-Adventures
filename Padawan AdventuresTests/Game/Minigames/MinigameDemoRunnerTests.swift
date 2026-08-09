import CoreGraphics
import SpriteKit
import Testing
@testable import Padawan_Adventures

@MainActor
final class RecordingDemoScript: MinigameDemoScript {
    private(set) var didRun = false

    func run(performer _: MinigameDemoPerforming, coins _: MinigameDemoCoinLayer) async {
        didRun = true
    }
}

@MainActor
final class FakeDemoStage: MinigameDemoStage {
    /// Scripted readiness / move sets. Advances one step after each *correct* move.
    private(set) var stepIndex = 0
    private let steps: [Step]
    private(set) var isFinishedFlag = false
    var demoDemonstratesPrelude = false
    var preludeMoves: [MinigameDemoMove] = []
    var script: MinigameDemoScript?
    /// Stands in for an animation that has to land before the move means anything
    /// (the deflected orb flying back to the monster).
    var isBusy = false

    struct Step {
        var moves: [MinigameDemoMove]
        /// When true, finishing this step (via a correct move) ends the demo.
        var finishesAfter: Bool = false
    }

    init(steps: [Step]) {
        self.steps = steps
    }

    var demoAcceptsInput: Bool {
        !isBusy && !isFinishedFlag && stepIndex < steps.count
    }

    var demoMoves: [MinigameDemoMove] {
        guard stepIndex < steps.count else { return [] }
        return steps[stepIndex].moves
    }

    var demoPreludeMoves: [MinigameDemoMove] { preludeMoves }

    var demoScript: MinigameDemoScript? { script }

    var demoCoinAnchor: CGPoint? {
        CGPoint(x: 10 * CGFloat(stepIndex + 1), y: 20)
    }

    var demoIsFinished: Bool { isFinishedFlag }

    func advanceAfterCorrectMove() {
        guard stepIndex < steps.count else { return }
        let finishes = steps[stepIndex].finishesAfter
        stepIndex += 1
        if finishes || stepIndex >= steps.count {
            isFinishedFlag = true
        }
    }

    func markFinished() {
        isFinishedFlag = true
    }
}

@MainActor
final class FakeDemoPerformer: MinigameDemoPerforming {
    private let stage: FakeDemoStage
    private(set) var performedIsCorrect: [Bool] = []
    private(set) var pauseDurations: [TimeInterval] = []
    /// When > 0, a correct move keeps the stage busy for this long before advancing.
    var busySeconds: TimeInterval = 0

    init(stage: FakeDemoStage) {
        self.stage = stage
    }

    func pause(_ seconds: TimeInterval) async {
        pauseDurations.append(seconds)
    }

    func perform(_ move: MinigameDemoMove, gestureSeconds _: TimeInterval) async {
        performedIsCorrect.append(move.isCorrect)
        // Wrong moves leave the stage on the same step (real scenes reshuffle in place).
        if move.isCorrect {
            if busySeconds > 0 {
                // Keep the stage busy after `perform` returns so `waitForConsequence`
                // has something to poll, matching a live animation still in flight.
                stage.isBusy = true
                let seconds = busySeconds
                let stage = self.stage
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    stage.isBusy = false
                    stage.advanceAfterCorrectMove()
                }
            } else {
                stage.advanceAfterCorrectMove()
            }
        }
    }
}

@MainActor
struct MinigameDemoRunnerTests {
    private func makeMove(isCorrect: Bool, x: CGFloat = 0) -> MinigameDemoMove {
        MinigameDemoMove(
            gesture: .tap(CGPoint(x: x, y: 0)),
            isCorrect: isCorrect,
            coinAnchor: CGPoint(x: x, y: 10)
        )
    }

    private func fastTiming() -> MinigameDemoRunner.Timing {
        var timing = MinigameDemoRunner.Timing()
        timing.coinHoldSeconds = 0.01
        timing.coinFlightSeconds = 0.01
        return timing
    }

    @Test func wrongThenPauseThenCorrectOrdering() async {
        let stage = FakeDemoStage(steps: [
            .init(
                moves: [makeMove(isCorrect: false, x: 1), makeMove(isCorrect: true, x: 2)],
                finishesAfter: true
            ),
        ])
        let performer = FakeDemoPerformer(stage: stage)
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let coins = MinigameDemoCoinLayer(scene: scene)
        var timing = fastTiming()
        timing.beatSeconds = 1.25
        timing.settleSeconds = 0.01
        timing.maxCorrectMoves = 6

        let runner = MinigameDemoRunner(
            stage: stage,
            performer: performer,
            coins: coins,
            timing: timing
        )
        let awarded = await runner.run()

        #expect(performer.performedIsCorrect == [false, true])
        #expect(performer.pauseDurations.contains(1.25))
        #expect(awarded == 1)
        #expect(coins.flightCount == 1)
    }

    @Test func respectsMaxCorrectMoves() async {
        let stage = FakeDemoStage(steps: [
            .init(moves: [makeMove(isCorrect: false, x: 0), makeMove(isCorrect: true, x: 1)]),
            .init(moves: [makeMove(isCorrect: true, x: 2)]),
            .init(moves: [makeMove(isCorrect: true, x: 3)]),
            .init(moves: [makeMove(isCorrect: true, x: 4)]),
            .init(moves: [makeMove(isCorrect: true, x: 5)]),
        ])
        let performer = FakeDemoPerformer(stage: stage)
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let coins = MinigameDemoCoinLayer(scene: scene)
        var timing = fastTiming()
        timing.beatSeconds = 0.01
        timing.settleSeconds = 0.01
        timing.maxCorrectMoves = 3

        let runner = MinigameDemoRunner(
            stage: stage,
            performer: performer,
            coins: coins,
            timing: timing
        )
        let awarded = await runner.run()

        let correctCount = performer.performedIsCorrect.filter { $0 }.count
        #expect(correctCount == 3)
        #expect(awarded == 3)
        #expect(coins.flightCount == 3)
        #expect(performer.performedIsCorrect.first == false)
    }

    @Test func waitUntilReadyReturnsWhenFinished() async {
        let stage = FakeDemoStage(steps: [
            .init(moves: [makeMove(isCorrect: true, x: 1)], finishesAfter: true),
        ])
        stage.markFinished()
        #expect(stage.demoIsFinished)

        let performer = FakeDemoPerformer(stage: stage)
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let coins = MinigameDemoCoinLayer(scene: scene)
        var timing = fastTiming()
        timing.readyTimeoutSeconds = 0.3

        let runner = MinigameDemoRunner(
            stage: stage,
            performer: performer,
            coins: coins,
            timing: timing
        )
        let awarded = await runner.run()
        #expect(performer.performedIsCorrect.isEmpty)
        #expect(awarded == 0)
    }

    @Test func preludeRunsBeforeWrongMoveAndAwardsNoCoins() async {
        let stage = FakeDemoStage(steps: [
            .init(
                moves: [makeMove(isCorrect: false, x: 1), makeMove(isCorrect: true, x: 2)],
                finishesAfter: true
            ),
        ])
        stage.demoDemonstratesPrelude = true
        stage.preludeMoves = [makeMove(isCorrect: false, x: 0)]
        let performer = FakeDemoPerformer(stage: stage)
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let coins = MinigameDemoCoinLayer(scene: scene)
        var timing = fastTiming()
        timing.beatSeconds = 0.01
        timing.settleSeconds = 0.01

        let runner = MinigameDemoRunner(
            stage: stage,
            performer: performer,
            coins: coins,
            timing: timing
        )
        let awarded = await runner.run()

        #expect(performer.performedIsCorrect == [false, false, true])
        #expect(awarded == 1)
    }

    @Test func scriptedStageSkipsGenericWrongThenRightPath() async {
        let stage = FakeDemoStage(steps: [
            .init(
                moves: [makeMove(isCorrect: false, x: 1), makeMove(isCorrect: true, x: 2)],
                finishesAfter: true
            ),
        ])
        let script = RecordingDemoScript()
        stage.script = script
        let performer = FakeDemoPerformer(stage: stage)
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let coins = MinigameDemoCoinLayer(scene: scene)

        let runner = MinigameDemoRunner(
            stage: stage,
            performer: performer,
            coins: coins,
            timing: fastTiming()
        )
        let awarded = await runner.run()

        #expect(script.didRun)
        #expect(performer.performedIsCorrect.isEmpty)
        #expect(awarded == 0)
    }

    @Test func waitsForConsequenceBeforeDroppingCoin() async {
        let stage = FakeDemoStage(steps: [
            .init(
                moves: [makeMove(isCorrect: false, x: 1), makeMove(isCorrect: true, x: 2)],
                finishesAfter: true
            ),
        ])
        let performer = FakeDemoPerformer(stage: stage)
        performer.busySeconds = 0.3
        let scene = SKScene(size: CGSize(width: 200, height: 200))
        let coins = MinigameDemoCoinLayer(scene: scene)
        var timing = fastTiming()
        timing.beatSeconds = 0.01
        timing.settleSeconds = 0.01

        let runner = MinigameDemoRunner(
            stage: stage,
            performer: performer,
            coins: coins,
            timing: timing
        )
        let started = Date()
        let awarded = await runner.run()
        let elapsed = Date().timeIntervalSince(started)

        #expect(awarded == 1)
        #expect(elapsed >= 0.3)
    }
}
