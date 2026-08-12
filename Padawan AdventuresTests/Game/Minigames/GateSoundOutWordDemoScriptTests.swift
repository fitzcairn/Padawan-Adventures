import CoreGraphics
import Foundation
import Testing
@testable import Padawan_Adventures

@MainActor
final class FakeGateStaging: GateSoundOutWordDemoStaging {
    struct Pass {
        var picture: CGPoint?
        var wordPlate: CGPoint?
        var choices: [GateSoundOutWordDemoCue]
        var wrong: MinigameDemoMove?
        var correct: MinigameDemoMove?
        var solvesWord: Bool
    }

    private var passes: [Pass]
    private(set) var passIndex = 0
    private(set) var restartCount = 0
    var isReady = true
    var isOver = false
    /// When true, `demoIsReady` stays false so `waitUntilReady` times out.
    var neverReady = false
    /// After this many restarts, mark the stage over so the forever loop can exit
    /// without relying solely on cooperative cancellation.
    var stopAfterRestarts: Int?

    init(passes: [Pass]) {
        self.passes = passes
    }

    private var current: Pass? {
        guard passIndex < passes.count else { return nil }
        return passes[passIndex]
    }

    var demoIsReady: Bool {
        !neverReady && isReady && !isOver && current != nil
    }

    var demoIsOver: Bool { isOver }

    var demoPictureTap: CGPoint? { current?.picture }
    var demoWordPlateTap: CGPoint? { current?.wordPlate }
    var demoChoiceTaps: [GateSoundOutWordDemoCue] { current?.choices ?? [] }
    var demoWordCueSeconds: TimeInterval { 0.01 }
    var demoLetterNameCueSeconds: TimeInterval { 0.01 }
    var demoWrongMove: MinigameDemoMove? { current?.wrong }
    var demoCorrectMove: MinigameDemoMove? { current?.correct }
    var demoIsWordSolved: Bool { current?.solvesWord == true }

    func demoRestart() {
        restartCount += 1
        if let stopAfterRestarts, restartCount >= stopAfterRestarts {
            isOver = true
            isReady = false
            return
        }
        isOver = false
        isReady = true
        // Leave `neverReady` alone so timeout-path tests keep stalling.
        if passIndex + 1 < passes.count {
            passIndex += 1
        }
    }

    func markSolvedAfterCorrect() {
        if current?.solvesWord == true {
            isOver = true
        } else if passIndex + 1 < passes.count {
            passIndex += 1
        }
    }
}

@MainActor
final class RecordingGatePerformer: MinigameDemoPerforming {
    private let stage: FakeGateStaging
    private(set) var gestures: [MinigameDemoMove.Gesture] = []
    private(set) var pauseDurations: [TimeInterval] = []

    init(stage: FakeGateStaging) {
        self.stage = stage
    }

    func pause(_ seconds: TimeInterval) async {
        pauseDurations.append(seconds)
        // Must actually suspend: a no-op pause lets the forever demo loop pin the
        // MainActor and deadlocks any test that tries to cancel it.
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    func perform(_ move: MinigameDemoMove, gestureSeconds _: TimeInterval) async {
        gestures.append(move.gesture)
        if move.isCorrect {
            stage.markSolvedAfterCorrect()
        }
    }
}

@MainActor
struct GateSoundOutWordDemoScriptTests {
    private func makeDrag(from: CGPoint, to: CGPoint, isCorrect: Bool) -> MinigameDemoMove {
        MinigameDemoMove(
            gesture: .drag(from: from, to: to),
            isCorrect: isCorrect,
            coinAnchor: to
        )
    }

    private func fastTiming() -> GateSoundOutWordDemoScript.Timing {
        var timing = GateSoundOutWordDemoScript.Timing()
        timing.gestureSeconds = 0.01
        timing.beatSeconds = 0.01
        timing.settleSeconds = 0.01
        timing.circuitHoldSeconds = 0.01
        timing.pollSeconds = 0.01
        timing.readyTimeoutSeconds = 2
        return timing
    }

    private func singlePass(
        solvesWord: Bool = true,
        picture: CGPoint? = CGPoint(x: 10, y: 90),
        wordPlate: CGPoint? = CGPoint(x: 10, y: 70)
    ) -> FakeGateStaging.Pass {
        let drop = CGPoint(x: 50, y: 50)
        return .init(
            picture: picture,
            wordPlate: wordPlate,
            choices: [
                GateSoundOutWordDemoCue(point: CGPoint(x: 20, y: 10), seconds: 0.01),
                GateSoundOutWordDemoCue(point: CGPoint(x: 40, y: 10), seconds: 0.01),
            ],
            wrong: makeDrag(from: CGPoint(x: 20, y: 10), to: drop, isCorrect: false),
            correct: makeDrag(from: CGPoint(x: 40, y: 10), to: drop, isCorrect: true),
            solvesWord: solvesWord
        )
    }

    @Test func firstPassGestureOrderAndCoinFlight() async {
        let stage = FakeGateStaging(passes: [singlePass()])
        stage.stopAfterRestarts = 1
        let performer = RecordingGatePerformer(stage: stage)
        var coinAnchors: [CGPoint] = []
        let script = GateSoundOutWordDemoScript(stage: stage, timing: fastTiming())

        await script.run(performer: performer) { point in
            coinAnchors.append(point)
        }

        #expect(performer.gestures.count >= 6)
        guard case let .tap(picture)? = performer.gestures[optional: 0] else {
            Issue.record("expected picture tap")
            return
        }
        #expect(picture == CGPoint(x: 10, y: 90))

        guard case let .tap(word)? = performer.gestures[optional: 1] else {
            Issue.record("expected word-plate tap")
            return
        }
        #expect(word == CGPoint(x: 10, y: 70))

        guard case let .tap(choice0)? = performer.gestures[optional: 2] else {
            Issue.record("expected first choice tap")
            return
        }
        #expect(choice0 == CGPoint(x: 20, y: 10))

        guard case let .tap(choice1)? = performer.gestures[optional: 3] else {
            Issue.record("expected second choice tap")
            return
        }
        #expect(choice1 == CGPoint(x: 40, y: 10))

        guard case let .drag(_, wrongTo)? = performer.gestures[optional: 4] else {
            Issue.record("expected wrong drag")
            return
        }
        #expect(wrongTo == CGPoint(x: 50, y: 50))

        guard case let .drag(_, correctTo)? = performer.gestures[optional: 5] else {
            Issue.record("expected correct drag")
            return
        }
        #expect(correctTo == CGPoint(x: 50, y: 50))
        #expect(coinAnchors.first == CGPoint(x: 50, y: 50))
        #expect(stage.restartCount >= 1)
    }

    @Test func solvedWordRestartsAndBeginsSecondPass() async {
        let stage = FakeGateStaging(passes: [
            singlePass(solvesWord: true, picture: CGPoint(x: 1, y: 1)),
            singlePass(solvesWord: true, picture: CGPoint(x: 2, y: 2)),
        ])
        stage.stopAfterRestarts = 2
        let performer = RecordingGatePerformer(stage: stage)
        var coinCount = 0
        let script = GateSoundOutWordDemoScript(stage: stage, timing: fastTiming())

        await script.run(performer: performer) { _ in
            coinCount += 1
        }

        #expect(stage.restartCount >= 1)
        #expect(coinCount >= 2)
        #expect(performer.gestures.contains { gesture in
            if case let .tap(point) = gesture { return point == CGPoint(x: 2, y: 2) }
            return false
        })
    }

    @Test func continueCueRunsBeforeTheSolvedWordRestart() async {
        let stage = FakeGateStaging(passes: [singlePass()])
        stage.stopAfterRestarts = 1
        let performer = RecordingGatePerformer(stage: stage)
        var restartCountsAtCue: [Int] = []
        let script = GateSoundOutWordDemoScript(stage: stage, timing: fastTiming())

        await script.run(performer: performer) { _ in } onLoopBoundary: {
            restartCountsAtCue.append(stage.restartCount)
        }

        // One cue per solved word, played while the finished circuit is still up.
        #expect(restartCountsAtCue == [0])
    }

    @Test func neverReadyStageRestartsInsteadOfReturning() async {
        let stage = FakeGateStaging(passes: [singlePass()])
        stage.neverReady = true
        stage.stopAfterRestarts = 1
        let performer = RecordingGatePerformer(stage: stage)
        var timing = fastTiming()
        timing.readyTimeoutSeconds = 0.05
        let script = GateSoundOutWordDemoScript(stage: stage, timing: timing)

        await script.run(performer: performer) { _ in }

        #expect(stage.restartCount >= 1)
        #expect(performer.gestures.isEmpty)
    }

    @Test func cancellingTaskEndsLoop() async {
        let stage = FakeGateStaging(passes: [singlePass()])
        let performer = RecordingGatePerformer(stage: stage)
        var timing = fastTiming()
        // Long enough that cancel races the first wait, not a finished pass.
        timing.readyTimeoutSeconds = 2
        let script = GateSoundOutWordDemoScript(stage: stage, timing: timing)
        // Keep the stage ready so the loop is live when we cancel.
        stage.neverReady = false

        let task = Task { @MainActor in
            await script.run(performer: performer) { _ in }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value
        #expect(task.isCancelled)
    }
}

private extension Array {
    subscript(optional index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
